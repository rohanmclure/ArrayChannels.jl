using Distributed

function main()
    if length(ARGS) != 2 || nprocs() == 1
        println("Usage: reduce -p n <# iterations> <vector_length>")
        exit(1)
    end

    argv = map(x -> parse(Int, x), ARGS)
    iterations, payload = argv

    ranks = nworkers()

    @sync for proc in workers()
        @spawnat proc begin
            global inbox = RemoteChannel(() -> Channel{Vector{Float64}}(0))
        end
    end

    futures = Vector{Future}(undef, ranks)
    @sync for proc in workers()
        futures[proc-1] = @spawnat proc begin
            reduce_channels = [(@fetchfrom proc get_channel()) for proc in sort(workers())]
            work(iterations, payload, inbox, reduce_channels)
        end
    end

    # Fetch results
    results = map(fetch, futures)
    value = results[1][1]
    time = maximum(map(x -> x[2], results))

    ground_truth = iterations+2.0+(iterations*iterations+5.0*iterations+4.0)*(ranks-1)/2;
    if abs(value - ground_truth) <= 1.e-8
        println("Solution validates")
    else
        println("Value provided: $value")
    end
    avgtime = time / iterations
    throughput = 1.e-6 * (2.0*ranks-1.0)*payload/avgtime
    println("Rate (MFlops/s): $throughput Avg time (s): $avgtime")
end

@everywhere function get_channel()
    return inbox
end

@everywhere function work(iterations, payload, local_channel, channels)
    local_sum = fill(1.0, payload)
    constant_vector = fill(1.0, payload)

    local t0, t1
    for k in 0:iterations
        if k == 1
            t0 = time_ns()
        end
        local_sum .+= constant_vector

        # Assign the accumulator
        if myid() == 2
            accumulator = copy(local_sum)
        else
            accumulator = local_sum
        end
        id_index = myid() - 1
        # z is the relative position variable in the reduction
        z = nprocs() - myid() + 1
        k = 0 # offset for who to collect from next
        while z % 2 == 0
            c = channels[id_index + 2^k]
            incoming = take!(c)
            accumulator .+= incoming
            z ÷= 2
            k += 1
        end

        if myid() != 2
            put!(local_channel, accumulator)
        end
    end

    t1 = time_ns()
    time = (t1-t0)*1.e-9

    if myid() == 2
        return (local_sum[1], time)
    else
        return (nothing, time)
    end
end

main()

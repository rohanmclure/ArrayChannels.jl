using Distributed

function main()
    if length(ARGS) != 2 || nprocs() == 1
        println("Usage: reduce -p n <# iterations> <vector_length>")
        exit(1)
    end

    argv = map(x -> parse(Int, x), ARGS)
    iterations, payload = argv

    @sync for proc in workers()
        @spawnat proc begin
            global vector = fill(1.0, payload)
            global ones = fill(1.0, payload)

            global inbox = RemoteChannel(() -> Channel{Vector{Float64}}(0))
        end
    end

    @sync for proc in workers()
        @spawnat proc begin
            reduce_channels = [(@fetchfrom proc get_channel()) for proc in sort(workers())]
            work(iterations, payload, vector, ones, inbox, reduce_channels)
        end
    end
end

@everywhere function get_channel()
    return inbox
end

@everywhere function work(iterations, payload, local_sum, constant_vector, local_channel, channels)
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
    if myid() == 2
        time = (t1 - t0) * 1e-9
        throughput = 1e-6 * (2.0*nworkers()-1)*payload * iterations / time
        println("$(throughput) MFlops/s")
    end
end

main()

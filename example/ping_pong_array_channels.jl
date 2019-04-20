include("../preload.jl")

function main()
    local iterations, payload
    if length(ARGS) == 0
        iterations, payload = 1000, 1000000
    elseif length(ARGS) == 2
        iterations, payload = map(x -> parse(Int,x), ARGS)
    else
        println("Usage: ping_pong_array_channels <# iterations> <vector_length>")
        exit(1)
    end

    # Allocate the array channel
    vector_channel = ArrayChannel(Float64, workers(), payload)

    @sync for proc in workers()
        @spawnat proc work(vector_channel, iterations, payload)
    end
end

@everywhere mean(l) = sum(l) / length(l)

@everywhere function work(vector_channel, iterations, payload)
    other_worker = myid() == 2 ? 3 : 2
    local t0, t1
    for k in 1 : 2 * iterations
        if k == iterations + 1
            t0 = time_ns()
        end

        if k % 2 == myid() - 2
            j = k % payload + 1
            i = if (j != 0) j else payload end
            vector_channel[i] += Float64(k)
            put!(vector_channel, other_worker)
        else
            take!(vector_channel)
        end
    end
    t1 = time_ns()

    throughput = iterations * payload * 8.0 * 1e-6 / ((t1-t0)*1e-9)

    if myid() == 2
        println("$throughput MB/s")
    end
end

main()

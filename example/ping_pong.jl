using Distributed
addprocs(2)

function main()
    if length(ARGS) != 2
        println("Usage: ping_pong <# iterations> <vector_length>")
        exit(1)
    end

    # Parse parameters
    argv = map(x -> parse(Int, x), ARGS)
    iterations, payload = argv

    # Setup the synchronous channels
    channels = [
        RemoteChannel(()->Channel{Vector{Float64}}(0), proc)
        for proc in workers()
    ]

    @sync for proc in workers()
        @spawnat proc work(iterations, payload, channels)
    end
end

@everywhere function work(iterations, payload, channels)
    partner_rank = if (myid() == 2) 3 else 2 end
    local_channel_ref = channels[myid()-1]
    other_channel_ref = channels[partner_rank-1]

    vector = Vector{Float64}(undef, payload)

    local t0, t1
    for k in 1 : iterations * 2
        if k == iterations + 1
            t0 = time_ns()
        end
        if k % 2 == myid() - 2
            j = k % payload + 1
            i = if (j != 0) j else payload end
            vector[i] += Float64(k)
            put!(other_channel_ref, vector)
        else
            vector = take!(local_channel_ref)
        end
    end
    t1 = time_ns()

    throughput = iterations * payload * 8.0 * 1e-6 / ((t1-t0)*1e-9)

    if myid() == 2
        println("Rate (MB/s): $throughput")
    end
end

main()

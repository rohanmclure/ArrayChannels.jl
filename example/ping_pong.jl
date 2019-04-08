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

    # Setup the synchronous channel
    @sync for proc in workers()
        @async remotecall_wait(proc) do
            global channel = RemoteChannel() do
                return Channel{Vector{Float64}}(0)
            end
        end
    end

    # Check to see that the master process has not overwritten channel references
    @sync for proc in workers()
        @async remotecall_wait(proc) do
            @assert channel.whence == myid()
        end
    end

    @sync for proc in workers()
        @async @fetchfrom proc work(iterations, payload)
    end
end

@everywhere function reference_channel()
    return channel
end

@everywhere function work(iterations, payload)
    partner_rank = if (myid() == 2) 3 else 2 end
    local_channel_ref = channel
    other_channel_ref = @fetchfrom partner_rank reference_channel()

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
        println("$throughput MB/s")
    end
end

main()

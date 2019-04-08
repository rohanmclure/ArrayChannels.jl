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
    vector_channel = ArrayChannel(Float64, payload)

    @sync for proc in workers()
        @async begin
            remotecall_wait(proc, vector_channel.rrid) do ref
                global id = ref
            end
            @fetchfrom proc work(iterations, payload)
        end
    end
end

@everywhere mean(l) = sum(l) / length(l)

@everywhere function work(iterations, payload)
    vector_channel = ac_get_from(id)

    local t0, t1
    for k in 1 : 2 * iterations
        if k == iterations + 1
            t0 = time_ns()
        end

        if k % 2 == myid() - 2
            j = k % payload + 1
            i = if (j != 0) j else payload end
            vector_channel[i] += Float64(k)
            put!(vector_channel, workers())
        else
            take!(vector_channel)
        end
    end
    t1 = time_ns()

    throughput = iterations * payload * 8.0 * 1e-6 / ((t1-t0)*1e-9)

    if myid() == 1
        println("$throughput MB/s")
    end
end

main()

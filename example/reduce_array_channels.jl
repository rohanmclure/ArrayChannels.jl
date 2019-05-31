# Rohan McLure, Australian National University (2019)
# Distributed implementation of the Reduce Parallel Research Kernel

using Distributed
@everywhere include("preload.jl")
@everywhere using ArrayChannels

function main()
    local iterations, payload
    if length(ARGS) != 2 || nprocs() == 1
        println("Usage: reduce -p n <# iterations> <vector_length>")
        exit(1)
    end

    argv = map(x -> parse(Int, x), ARGS)
    iterations, payload = argv

    ranks = nworkers()

    A = ArrayChannel(Float64, workers(), payload)

    futures = Vector{Future}(undef, ranks)
    @sync for proc in workers()
        futures[proc-1] = @spawnat proc work(A, 2, iterations, payload)
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

@everywhere mean(l) = sum(l) / length(l)

@everywhere function work(A, root, iterations, payload)
    local t0, t1
    A_data = A.buffer.src
    constant_vector = ones(payload)
    for k in 0 : iterations
        if k == 1
            t0 = time_ns()
        end

        A_data .+= constant_vector
        reduce!(+, A, root)
    end

    t1 = time_ns()
    time = (t1-t0)*1.e-9

    if myid() == root
        return (A[1], time)
    else
        return (nothing, time)
    end
end

main()

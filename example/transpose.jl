# Rohan McLure, Australian National University (2019)
# Distributed implementation of the Transpose Parallel Research Kernel
using Distributed

function main()
    # Parameters
    local iterations, order
    if length(ARGS) != 2 || nprocs() == 1
        ("Usage: julia -p <# workers> transpose.jl <# iterations> <# order>")
        exit(1)
    else
        argv = map(x -> parse(Int, x), ARGS)
        iterations, order = argv
    end

    if order % nworkers() != 0
        println("Number of workers must divide order of matrix")
        exit(1)
    end

    # Rank setup
    rank = nworkers()

    # Dimension setup
    std_dim = Int(order / rank)
    RC = RemoteChannel{Channel{Matrix{Float64}}}

    # Setup channels
    in_channels = Vector{Vector{Union{RC, Nothing}}}(undef, rank)
    out_channels = Vector{Vector{Union{RC, Nothing}}}(undef, rank)
    for i in 1:rank
        in_channels[i] = Vector{Union{RC, Nothing}}(undef, rank)
        out_channels[i] = Vector{Union{RC, Nothing}}(undef, rank)
    end

    channel_lambda = () -> Channel{Matrix{Float64}}(0)

    for i in 1:rank
        for j in 1:rank
            if i == j
                in_channels[i][j] = nothing
            end
            in_channels[i][j] = RemoteChannel(channel_lambda, workers()[i])
        end
    end

    for i in 1:rank
        for j in 1:rank
            out_channels[i][j] = in_channels[j][i]
        end
    end

    dims = (order, std_dim)

    futures = Vector{Future}(undef, rank)
    @sync for k in 1 : rank
        in_c = in_channels[k]
        out_c = out_channels[k]
        futures[k] = @spawnat workers()[k] work(dims, in_c, out_c, iterations)
    end

    epsilon = 1.e-8
    results = map(fetch, futures)
    abserr = sum(map(x -> x[1], results))
    time = maximum(map(x -> x[2], results))
    nbytes = 2 * order^2 * 8

    if abserr < epsilon
        println("Solution validates")
    else
        println("error ",abserr, " exceeds threshold ",epsilon)
        println("ERROR: solution did not validate")
    end

    avgtime = time/iterations
    println("Rate (MB/s): ",1.e-6*nbytes/avgtime, " Avg time (s): ", avgtime)
end

# Local transpose operation
@inline @everywhere function do_transpose!(A, B, order)
    for jt in 1 : 32 : order
        for it in 1 : 32 : order
            for j in jt : min(jt+32-1, order)
                for i in it : min(it+32-1, order)
                    @inbounds B[i,j] += A[j,i]
                    @inbounds A[j,i] += 1.0
                end
            end
        end
    end
end

# Same function as do_transpose!, but just reassigns output
@inline @everywhere function write_block!(A, B, order)
    for jt in 1 : 32 : order
        for it in 1 : 32 : order
            for j in jt : min(jt+32-1, order)
                for i in it : min(it+32-1, order)
                    @inbounds B[i,j] = A[j,i]
                    @inbounds A[j,i] += 1.0
                end
            end
        end
    end
end

@everywhere function work(
    dims::Tuple{Int,Int}, # First component will be order
    in_channels::Vector{Union{RemoteChannel{Channel{Matrix{Float64}}}, Nothing}},
    out_channels::Vector{Union{RemoteChannel{Channel{Matrix{Float64}}}, Nothing}},
    iterations::Int
)
    # Set up local process data
    id = myid()
    n = nworkers()
    order, width_local = dims

    # Local 'column blocks' of the dist. matrix
    A = zeros(dims...)
    B = zeros(dims...)
    for i in 1:order
        for j in 1:width_local
            jl = j + (id-2)*width_local
            A[i,j] = order * (jl - 1) + (i - 1)
        end
    end

    # Views into the diagonal block
    local_frame_A = view(A, (id-2)*width_local+1:(id-1)*width_local, :)
    local_frame_B = view(B, (id-2)*width_local+1:(id-1)*width_local, :)

    # Arrays used for communication blocks
    local block_in
    block_out = Matrix{Float64}(undef, width_local, width_local)

    local t0, t1
    for k in 0 : iterations
        if k == 1
            t0 = time_ns()
        end

        do_transpose!(local_frame_A, local_frame_B, width_local)

        for phase in 1 : n-1
            send_idx = (id-2 + phase) % n + 1
            recv_idx = (id-2 + n - phase) % n + 1

            inbox = in_channels[recv_idx]
            outbox = out_channels[send_idx]

            frame = view(A, (send_idx-1)*width_local+1:send_idx*width_local, :)
            write_block!(frame, block_out, width_local)

            @sync begin
                @async begin
                    frame = view(B, (recv_idx-1)*width_local+1:recv_idx*width_local, :)
                    block_in = take!(inbox)
                    frame .+= block_in
                end
                @async begin
                    put!(outbox, block_out)
                end
            end
        end
    end
    t1 = time_ns()

    # Validate the local solution - sending the error back to master
    addit = (0.5*iterations) * (iterations+1)
    abserr = 0.0
    for i in 1:order
        for j in 1:width_local
            jl = j + (id-2)*width_local
            temp = (order * (i-1) + (jl-1)) * (iterations+1)
            @inbounds abserr = abserr + abs(B[i,j] - (temp+addit))
        end
    end
    return (abserr, (t1-t0)*1.e-9)
end

main()

# Rohan McLure, Australian National University (2019)
# Distributed implementation of the (Star) Stencil Parallel Research Kernel
using Distributed

function main()
    if length(ARGS) != 3 || nprocs() == 1
        println("Usage: julia -p <# workers> stencil.jl <# iterations> <# order> <# radius>")
        exit(1)
    end

    argv = map(x -> parse(Int, x), ARGS)
    iterations, order, r = argv
    ranks = nworkers()
    procs_x, procs_y = factor(ranks)
    println("Factoring: x=$procs_x, y=$procs_y")
    out_channels = Matrix{Vector{Union{RemoteChannel,Nothing}}}(undef, procs_y, procs_x)
    dims = Matrix{Tuple{Int,Int}}(undef, procs_y, procs_x)
    std_width = Int(ceil(order / procs_x))
    std_height = Int(ceil(order / procs_y))
    last_width = order % std_width == 0 ? std_width : order % std_width
    last_height = order % std_height == 0 ? std_height : order % std_height
    for i in 1:procs_y
        for j in 1:procs_x
            v = Vector{Union{RemoteChannel, Nothing}}(undef, 4)
            v[1] = i != 1 ? RemoteChannel(() -> Channel{Matrix{Float64}}(0), (i-2)*procs_x+j) : nothing
            v[2] = j != procs_x ? RemoteChannel(() -> Channel{Matrix{Float64}}(0), (i-1)*procs_x+j+1) : nothing
            v[3] = i != procs_y ? RemoteChannel(() -> Channel{Matrix{Float64}}(0), i*procs_x+j) : nothing
            v[4] = j != 1 ? RemoteChannel(() -> Channel{Matrix{Float64}}(0), (i-1)*procs_x+j-1) : nothing
            out_channels[i,j] = v
            # Assigning coordinates
            height = i == procs_y ? last_height : std_height
            width = j == procs_x ? last_width : std_width
            dims[i,j] = (height, width)
        end
    end
    in_channels = Matrix{Vector{Union{RemoteChannel,Nothing}}}(undef, procs_y, procs_x)
    for i in 1:procs_y
        for j in 1:procs_x
            v = Vector{Union{RemoteChannel, Nothing}}(undef, 4)
            v[1] = i != 1 ? out_channels[i-1,j][3] : nothing
            v[2] = j != procs_x ? out_channels[i,j+1][4] : nothing
            v[3] = i != procs_y ? out_channels[i+1,j][1] : nothing
            v[4] = j != 1 ? out_channels[i,j-1][2] : nothing
            in_channels[i,j] = v
        end
    end

    futures = Matrix{Future}(undef, procs_y, procs_x)
    @sync for i in 1:procs_y
        for j in 1:procs_x
            wid = (i-1)*procs_x+j
            id = workers()[wid]
            futures[i,j] = @spawnat id do_stencil(iterations, order, dims[i,j], (i,j), (procs_y, procs_x), r, out_channels[i,j], in_channels[i,j])
        end
    end

    results = map(fetch, futures)

    active_points = (order - 2*r)^2
    norm = sum(map(x->x[1], results))
    norm /= active_points
    time = maximum(map(x->x[2], results))
    reference_norm = 2 * (iterations + 1)
    if abs(norm - reference_norm) > 1.e-8
        println("ERROR: L1 norm = $norm Reference L1 norm = $reference_norm")
    else
        println("Solution validates")
    end
    stencil_size = 4*r+1
    flops = (2*stencil_size+1) * active_points
    avgtime = time/iterations
    println("Rate (MFlops/s): ",1.e-6*flops/avgtime, " Avg time (s): ",avgtime)
end

@everywhere function do_stencil(
    iterations::Int,
    order::Int,
    local_dims::Tuple{Int,Int},
    proc_dims::Tuple{Int,Int},
    proc_setup::Tuple{Int,Int},
    r::Int,
    out_channels::Vector{Union{RemoteChannel,Nothing}},
    in_channels::Vector{Union{RemoteChannel,Nothing}}
)
    ub, rb, db, lb = out_channels .!== nothing
    h, w = local_dims
    id_y, id_x = proc_dims
    procs_y, procs_x = proc_setup
    std_height, std_width = Int(ceil(order/procs_y)), Int(ceil(order/procs_x))
    i_start, j_start = (id_y-1)*std_height, (id_x-1)*std_width
    i_end, j_end = i_start + h - 1, j_start + w - 1
    println("ub: $ub, rb: $rb, db: $db, lb: $lb")
    println("Local chunk: ($i_start, $j_start)")
    i_o_start, j_o_start = (ub ? 1 : r+1), (lb ? 1 : r+1)
    i_o_end, j_o_end = (db ? h : h-r), (rb ? w : w-r)
    println("Working on: ($i_o_start : $i_o_end), ($j_o_start : $j_o_end)")
    A = zeros(Float64, (local_dims .+ 2*r)...)
    for i in 1:h
        for j in 1:w
            A[i+r,j+r] = (i_start + i - 1) + (j_start + j - 1)
        end
    end
    B = zeros(Float64, local_dims...)
    W = zeros(Float64, 2*r+1, 2*r+1)
    for i in 1:r
        W[r+1, r+i+1] = 1.0/(2*i*r)
        W[r+i+1, r+1] = 1.0/(2*i*r)
        W[r+1, r-i+1] = -1.0/(2*i*r)
        W[r-i+1, r+1] = -1.0/(2*i*r)
    end

    u_out, r_out, d_out, l_out = [Matrix{Float64}(undef, (i % 2 == 0 ? (h,r) : (r,w))...) for i in 1:4]
    u_out_v, r_out_v, d_out_v, l_out_v = [
        view(A, r+1:2*r, r+1:r+w),
        view(A, r+1:r+h, w+1:r+w),
        view(A, h+1:r+h, r+1:r+w),
        view(A, r+1:r+h, r+1:2*r)
    ]
    u_in_v, r_in_v, d_in_v, l_in_v = [
        view(A, 1:r, r+1:r+w),
        view(A, r+1:r+h, r+w+1:2*r+w),
        view(A, r+h+1:2*r+h, r+1:r+w),
        view(A, r+1:r+h, 1:r)
    ]

    # Channels
    u_out_c, r_out_c, d_out_c, l_out_c = out_channels
    u_in_c, r_in_c, d_in_c, l_in_c = in_channels

    local t0, t1

    for k in 0 : iterations
        if k == 1
            t0 = time_ns()
        end
        # Send
        @sync begin
            if ub
                @async begin
                    copy!(u_out, u_out_v)
                    put!(u_out_c, u_out)
                end
                @async begin
                    u_in = take!(u_in_c)
                    copy!(u_in_v, u_in)
                end
            end
            if rb
                @async begin
                    copy!(r_out, r_out_v)
                    put!(r_out_c, r_out)
                end
                @async begin
                    r_in = take!(r_in_c)
                    copy!(r_in_v, r_in)
                end
            end
            if db
                @async begin
                    copy!(d_out, d_out_v)
                    put!(d_out_c, d_out)
                end
                @async begin
                    d_in = take!(d_in_c)
                    copy!(d_in_v, d_in)
                end
            end
            if lb
                @async begin
                    copy!(l_out, l_out_v)
                    put!(l_out_c, l_out)
                end
                @async begin
                    l_in = take!(l_in_c)
                    copy!(l_in_v, l_in)
                end
            end
        end

        for j in j_o_start : j_o_end
            for i in i_o_start : i_o_end
                tmp = 0.0
                for ii in -r:r
                    @inbounds tmp += W[r+ii+1, r+1] * A[i+ii+r, j+r]
                end
                for jj in -r:-1
                    @inbounds tmp += W[r+1, r+jj+1] * A[i+r, j+jj+r]
                end
                for jj in 1:r
                    @inbounds tmp += W[r+1, r+jj+1] * A[i+r, j+jj+r]
                end
                @inbounds B[i,j] += tmp
            end
        end

        for j in 1:w
            for i in 1:h
                @inbounds A[i+r, j+r] += 1.0
            end
        end
    end

    t1 = time_ns()

    local_norm = 0.0
    for i in i_o_start : i_o_end
        for j in j_o_start : j_o_end
            local_norm += abs(B[i,j])
        end
    end

    return (local_norm, (t1-t0)*1.e-9)
end

function factor(x::Int)
    s = Int(floor(sqrt(x)))
    for p in s:-1:1
        if x % p == 0
            return (p, x ÷ p)
        end
    end
end

main()

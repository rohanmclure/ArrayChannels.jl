# Rohan McLure, Australian National University (2019)
# Distributed implementation of the (Star) Stencil Parallel Research Kernel
# Making use of the ArrayChannels.jl library for Julia
# https://github.com/rohanmclure/ArrayChannels.jl
@everywhere using ArrayChannels

function main()
    if length(ARGS) != 3 || nprocs() == 1
        println("Usage: julia -p <# workers> stencil_array_channels.jl <# iterations> <# order> <# radius>")
        exit(1)
    end

    argv = map(x -> parse(Int, x), ARGS)
    iterations, order, r = argv
    procs_x, procs_y = factor(nworkers())

    # Channel setup
    out_channels = Matrix{Vector{Union{ArrayChannel,Nothing}}}(undef, procs_y, procs_x)
    in_channels = Matrix{Vector{Union{ArrayChannel,Nothing}}}(undef, procs_y, procs_x)
    dims = Matrix{Tuple{Int,Int}}(undef, procs_y, procs_x)

    # Dimension setup
    std_width = Int(ceil(order / procs_x))
    std_height = Int(ceil(order / procs_y))
    last_width = order % std_width == 0 ? std_width : order % std_width
    last_height = order % std_height == 0 ? std_height : order % std_height

    for i in 1:procs_y
        for j in 1:procs_x
            h = i == procs_y ? last_height : std_height
            w = j == procs_x ? last_width : std_width

            v = Vector{Union{ArrayChannel, Nothing}}(undef, 4)
            id = workers()[(i-1)*procs_x+j]
            v[1] = i != 1 ? ArrayChannel(Float64, [id, id-procs_x], r, w) : nothing
            v[2] = j != procs_x ? ArrayChannel(Float64, [id, id+1], h, r) : nothing
            v[3] = i != procs_y ? ArrayChannel(Float64, [id, id+procs_x], r, w) : nothing
            v[4] = j != 1 ? ArrayChannel(Float64, [id, id-1], h, r) : nothing

            dims[i,j] = (h,w)
            out_channels[i,j] = v
        end
    end

    for i in 1:procs_y
        for j in 1:procs_x
            v = Vector{Union{ArrayChannel,Nothing}}(undef, 4)
            v[1] = i != 1 ? out_channels[i-1,j][3] : nothing
            v[2] = j != procs_x ? out_channels[i,j+1][4] : nothing
            v[3] = i != procs_y ? out_channels[i+1,j][1] : nothing
            v[4] = j != 1 ? out_channels[i,j-1][2] : nothing
            in_channels[i,j] = v
        end
    end
    futures = Matrix{Future}(undef, procs_y, procs_x)
    @sync for i in 1 : procs_y
        for j in 1:procs_x
            futures[i,j] = @spawnat workers()[(i-1)*procs_x+j] begin
                do_stencil(order, iterations, dims[i,j], (procs_x, procs_y), r, out_channels[i,j], in_channels[i,j])
            end
        end
    end

    # Concatenate the outputs
    results = map(fetch, futures)
    norm = sum(map(x->x[1], results))
    time = maximum(map(x->x[2], results))

    # Verify the result
    active_points = (order-2*r)^2
    norm /= active_points
    epsilon=1.e-8
    reference_norm = 2*(iterations+1)
    if abs(norm-reference_norm) < epsilon
        println("Solution validates")
        stencil_size = 4*r+1 # Star
        flops = (2*stencil_size+1) * active_points
        avgtime = time/iterations
        println("Rate (MFlops/s): $(1.e-6*flops/avgtime) Avg time (s):  $avgtime")
    else
        println("ERROR: L1 norm = $norm Reference L1 norm = $reference_norm")
        exit(9)
    end
end

@everywhere function do_stencil(
    order,
    iterations::Int,
    local_dims::Tuple{Int,Int},
    proc_dims::Tuple{Int,Int},
    r::Int,
    out_channels::Vector{Union{ArrayChannel,Nothing}},
    in_channels::Vector{Union{ArrayChannel,Nothing}}
)
    # Flags for whether workers exist above, rightward ... of this rank
    ub, rb, db, lb = out_channels .!== nothing
    h, w = local_dims

    # Initialise A
    A = zeros(Float64, (local_dims .+ 2*r)...)
    A_central = view(A, r+1:r+h, r+1:r+w)
    procs_x, procs_y = proc_dims
    id = myid() - 2
    p_i, p_j = (id ÷ procs_x, id % procs_x)
    # Start coordinate in global coordinates
    std_height, std_width = Int(ceil(order / procs_y)), Int(ceil(order / procs_x))
    i_start, j_start = p_i * std_height, p_j * std_width
    i_o_start, j_o_start = (ub ? 1 : r+1), (lb ? 1 : r+1)
    i_o_end, j_o_end = (db ? h : h-r), (rb ? w : w-r)
    for i in 1:h
        for j in 1:w
            A_central[i,j] = (p_i*std_height + i - 1.0) + (p_j*std_width + j - 1.0)
        end
    end

    # Initialise output array
    B = zeros(Float64, local_dims...)
    # Discrete Divergence operator
    W = zeros(Float64, 2*r+1, 2*r+1)
    for i in 1:r
        W[r+1, r+i+1] = 1.0/(2*i*r)
        W[r+i+1, r+1] = 1.0/(2*i*r)
        W[r+1, r-i+1] = -1.0/(2*i*r)
        W[r-i+1, r+1] = -1.0/(2*i*r)
    end

    u_out_v, r_out_v, d_out_v, l_out_v = [
        view(A, r+1:2*r, r+1:r+w),
        view(A, r+1:r+h, w+1:r+w),
        view(A, h+1:r+h, r+1:r+w),
        view(A, r+1:r+h, r+1:2+r)
    ]
    u_in_v, r_in_v, d_in_v, l_in_v = [
        view(A, 1:r, r+1:r+w),
        view(A, r+1:r+h, r+w+1:2*r+w),
        view(A, r+h+1:2*r+h, r+1:r+w),
        view(A, r+1:r+h, 1:r)
    ]
    # Proc ID references
    id = myid()
    u_id, r_id, d_id, l_id = [
        id - procs_x,
        id + 1,
        id + procs_x,
        id - 1
    ]

    # Channels
    u_out_c, r_out_c, d_out_c, l_out_c = out_channels
    u_in_c, r_in_c, d_in_c, l_in_c = in_channels

    local t0, t1

    for k in 0 : iterations
        if k == 1
            t0 = time_ns()
        end
        # Send / Receive
        @sync begin
            if ub
                @async begin
                    copy!(u_out_c, u_out_v)
                    put!(u_out_c, u_id)
                end
                @async begin
                    take!(u_in_c, u_id)
                    copy!(u_in_v, u_in_c)
                end
            end
            if rb
                @async begin
                    copy!(r_out_c, r_out_v)
                    put!(r_out_c, r_id)
                end
                @async begin
                    take!(r_in_c, r_id)
                    copy!(r_in_v, r_in_c)
                end
            end
            if db
                @async begin
                    copy!(d_out_c, d_out_v)
                    put!(d_out_c, d_id)
                end
                @async begin
                    take!(d_in_c, d_id)
                    copy!(d_in_v, d_in_c)
                end
            end
            if lb
                @async begin
                    copy!(l_out_c, l_out_v)
                    put!(l_out_c, l_id)
                end
                @async begin
                    take!(l_in_c, l_id)
                    copy!(l_in_v, l_in_c)
                end
            end
        end

        for j in j_o_start : j_o_end
            for i in i_o_start : i_o_end
                # Star case
                tmp = 0.0
                for jj in -r:r
                    @inbounds tmp += W[r+1, r+1+jj] * A[i+r, j+jj+r]
                end
                for ii in -r:-1
                    @inbounds tmp += W[r+1+ii, r+1] * A[i+ii+r, j+r]
                end
                for ii in 1:r
                    @inbounds tmp += W[r+1+ii, r+1] * A[i+ii+r, j+r]
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

    norm = 0.0
    for i in i_o_start : i_o_end
        for j in j_o_start : j_o_end
            norm += abs(B[i,j])
        end
    end
    return (norm, (t1-t0)*1.e-9)
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

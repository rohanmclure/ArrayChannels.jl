# Rohan McLure, 2018

mutable struct ArrayChannel{AT} <: AbstractChannel{AT} where AT <: Array{T}

    cond_take::Condition
    cond_put::Condition
    buffers::Vector{AT}
    sz_max::Integer
    current_sz::Integer

    # Constructor accepting floats for size
    function ArrayChannel{AT}(sz::Float64, dims::NTuple{Int64}) where AT <: Array{T}
        if sz == Inf
            ArrayChannel{AT}(typemax(Int), dims)
        else
            ArrayChannel{AT}(convert(Int,sz), dims)
        end
    end

    # Main constructor
    function ArrayChannel{AT})(sz::Integer, dims::NTuple{Int64}) where AT <: Array{T}
        if sz <= 0
            throw(ArgumentError("Array Channels should have a positive number of buffers"))
        end
        ch = new(Vector{AT}(sz), sz, 0)
        # Allocate sz arrays
        for i in 1 : sz
            ch[i] = Array{T}(undef,dims)
        end
    end
end

# Buffered put! only
function put!(ac::ArrayChannel{AT}, v::AT, locs::NTuple{Range}) where AT <: Array{T}
    while ac.current_sz == ac.sz_max
        wait(ac.cond_put)
    end

    ac.current_sz += 1
    copyto!(ac.buffers[ac.current_sz], v, locs)

    notify(c.cond_take, nothing, true, false)

    view(v, locs)
end

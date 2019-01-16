# Rohan McLure, 2018

using Base
import Base: AbstractChannel, put!, take!

# Currently a synchronous buffer for in-place communication of array data.
mutable struct ArrayChannel{T,N} <: AbstractChannel where {T,N}
    cond_take::Condition
    cond_put::Condition
    buffer::InPlaceArray{T,N}

    # Main constructor
    function ArrayChannel{AT})(dims::NTuple{Int64}) where AT <: DenseArray{T}
        ch = new(Condition(), Condition(), AT(undef, dims...))
    end

    function ArrayChannel(A::AT) where AT <: DenseArray{T}
        ch = new(Condition(), Condition(), A)
    end
end

function put!(ac::ArrayChannel{T,N}) where {T,N}
    wait(ac.cond_put)

    # Wait for others to have enabled a `take!`
    target_processes = workers() # A start

    @sync for proc in target_processes
        @async remotecall_wait(proc, ac.rrid) do id
            # From the rrid, get the ArrayChannel reference, and wait on cond_take
            wait(ac = references[id].cond_take)
        end
    end

    @sync for proc in target_processes
        @async @fetchfrom ac.buffer
    end
end

function take!(ac::ArrayChannel{T,N}) where {T,N}
    wait(ac.cond_take)
end

global references = Dict{RRID, ArrayChannel}()

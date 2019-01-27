# Rohan McLure, 2018

using Distributed
import Distributed: RRID, WorkerPool

using Base
import Base: AbstractChannel, put!, take!, show, getindex, setindex!
include("inplacearray.jl")

"""
Channel construct with getindex, setindex! overrides. Implements an array construct that may be 'committed' for synchronisation with any number of distributed workers after acknowledging a 'take!' from the recipients.
"""
mutable struct ArrayChannel
    cond_take::Condition
    cond_put::Condition
    buffer::InPlaceArray
    rrid::RRID

    # Main constructor
    function ArrayChannel(T::Type, dim...)
        ch = new(Condition(), Condition(), InPlaceArray(Array{T}(undef, dims...)), RRID())
        @sync for proc in workers()
            if proc != myid()
                @async remotecall_wait(proc, ch.rrid, ch.buffer) do id, buffer
                    references[id] = ArrayChannel(buffer, id)
                end
            end
        end
        references[ch.rrid] = ch
        return ch
    end

    function ArrayChannel(A::InPlaceArray, id::RRID)
        new(Condition(), Condition(), A, id)
    end

    function ArrayChannel(A::AT) where {AT}
        ch = new(Condition(), Condition(), A, RRID())
    end
end

"""
put! initiates two blocking remotecalls for each worker in the workerpool. The first waits on the receiver to authorises the buffer to be overwritten, the second writes the data.
"""
function put!(ac::ArrayChannel)
    # Wait for others to have enabled a `take!`
    target_processes = workers() # A start

    @sync for proc in target_processes
        @async remotecall_wait(proc, ac.rrid) do id
            # From the rrid, get the ArrayChannel reference, and wait on cond_take
            wait(references[id].cond_take)
        end
    end

    @sync for proc in target_processes
        @async @fetchfrom proc ac.buffer; notify(ac.cond_put)
    end
end

"""
take! signals to the other owners of the ArrayChannel the intention to overwrite the buffer with new array data. Will block the caller.
"""
function take!(ac::ArrayChannel)
    notify(ac.cond_take)
    wait(ac.cond_put)
    return ac.buffer
end

# Required to show InPlaceArray objects
function show(S::IO, ac::ArrayChannel)
	invoke(show, Tuple{IO, InPlaceArray}, S, ac.buffer::InPlaceArray)
end

function show(S::IO, mime::MIME"text/plain", ac::InPlaceArray)
    invoke(show, Tuple{IO, MIME"text/plain", InPlaceArray}, S, MIME"text/plain"(), ac.buffer)
end

function getindex(ac::ArrayChannel, keys...)
    getindex(ac.buffer.src, keys...)
end

function setindex!(ac::ArrayChannel, v, keys...)
    setindex!(ac.buffer.src, v, keys...)
end

global references = Dict{RRID, ArrayChannel}()

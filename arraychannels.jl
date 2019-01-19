# Rohan McLure, 2018

using Distributed
import Distributed: RRID, WorkerPool

using Base
import Base: AbstractChannel, put!, take!, show
include("inplacearray.jl")

# Currently a synchronous buffer for in-place communication of array data.
mutable struct ArrayChannel
    cond_take::Condition
    cond_put::Condition
    buffer::InPlaceArray
    rrid::RRID

    # Main constructor
    function ArrayChannel(T::Type, dims...)
        ch = new(Condition(), Condition(), InPlaceArray(Array{T}(undef, dims...)), RRID())
        @sync for proc in workers()
            if proc != myid()
                @async remotecall_wait(proc, ch.rrid) do id
                    refernces[id] = ArrayChannel()
                end
            end
        end
        references[ch.rrid] = ch
        return ch
    end

    function ArrayChannel(A::AT) where {AT}
        ch = new(Condition(), Condition(), A, RRID())
    end
end

function put!(ac::ArrayChannel)
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
        @async @fetchfrom proc ac.buffer
    end
end

function take!(ac::ArrayChannel)
    wait(ac.cond_take)
end

# Required to show InPlaceArray objects
function show(S::IO, ac::ArrayChannel)
	invoke(show, Tuple{IO, InPlaceArray}, S, ac.buffer::InPlaceArray)
end

function show(S::IO, mime::MIME"text/plain", ac::InPlaceArray)
    invoke(show, Tuple{IO, MIME"text/plain", InPlaceArray}, S, MIME"text/plain"(), ac.buffer)
end

global references = Dict{RRID, ArrayChannel}()

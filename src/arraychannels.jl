# Rohan McLure, 2018

include("inplacearray.jl")

"""
Channel construct with getindex, setindex! overrides. Implements an array construct that may be 'committed' for synchronisation with any number of distributed workers after acknowledging a 'take!' from the recipients.
"""
mutable struct ArrayChannel
    cond_take::Event
    cond_put::Event
    buffer::InPlaceArray
    rrid::RRID

    # Headless constructor
    function ArrayChannel(A::InPlaceArray, id::RRID)
        new(Event(), Event(), A, id)
    end

    # Main constructor
    function ArrayChannel(T::Type, dims...)
        ipa = InPlaceArray(Array{T}(undef, dims...))
        ch = new(Event(), Event(), ipa, RRID())
        @sync for proc in procs()
            if proc != myid()
                @async remotecall_wait(proc, ch.rrid, ch.buffer.rrid) do ch_id, arr_id
                    # Link to preallocated InPlaceArray
                    replica = InPlaceArray(places[arr_id], arr_id)
                    channels[ch_id] = ArrayChannel(replica, ch_id)
                end
            else
                @async channels[ch.rrid] = ch
            end
        end
        return ch
    end
end

function get_arraychannel(id::RRID)
    return channels[id]
end

"""
put! initiates two blocking remotecalls for each worker in the workerpool. The first waits on the receiver to authorises the buffer to be overwritten, the second writes the data.
"""
function put!(ac::ArrayChannel, participants=procs())
    # Wait for others to have enabled a `take!`
    target_processes = [proc for proc in participants if proc != myid()]

    id = ac.rrid
    place = ac.buffer

    @sync for proc in target_processes
        @async remotecall_wait(proc, id) do id
            # From the rrid, get the ArrayChannel reference, and wait on cond_take
            X = get_arraychannel(id)
            wait(X.cond_take)
        end
    end

    @sync for proc in target_processes
        @async remotecall_wait(proc, id, place) do id, payload
            # Serialise the InPlaceArray, but do nothing with it.
            X = get_arraychannel(id)
            notify(X.cond_put)
        end
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

function ac_get_from(id::RRID)
    if id in keys(channels)
        return channels[id]
    end
    nothing
end

global channels = Dict{RRID, ArrayChannel}()

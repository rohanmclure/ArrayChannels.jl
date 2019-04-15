# Rohan McLure, 2018

"""
Channel construct with getindex, setindex! overrides. Implements an array construct that may be 'committed' for synchronisation with any number of distributed workers after acknowledging a 'take!' from the recipients.
"""
mutable struct ArrayChannel
    lock::ReentrantLock
    cond_take::Event
    cond_put::Event
    buffer::Union{Nothing, InPlaceArray}
    rrid::RRID

    # Null constructor
    function ArrayChannel(id::RRID)
        ch = new(ReentrantLock(), Event(), Event(), nothing, id)
        channels[id] = ch
        return ch
    end

    # Headless constructor
    function ArrayChannel(A::InPlaceArray, id::RRID)
        ch = new(ReentrantLock(), Event(), Event(), A, id)
        channels[id] = ch
        return ch
    end

    # Main constructor
    function ArrayChannel(T::Type, participants::Vector{Int64}, dims...)
        id = RRID()
        ch = new(ReentrantLock(), Event(), Event(), nothing, id)
        @sync for proc in participants
            if proc == myid()
                @async begin
                    ipa = InPlaceArray(Array{T}(undef, dims...), id)
                    ch.buffer = ipa
                    channels[id] = ch
                end
            else
                @spawnat proc begin
                    ipa = InPlaceArray(Array{T}(undef, dims...), id)
                    ArrayChannel(ipa, id)
                end
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
function put!(ac::ArrayChannel, send_to::Int64)
    lock(ac.lock) do
        id = ac.rrid
        place = ac.buffer
        remotecall_wait(send_to, id) do id
            # From the rrid, get the ArrayChannel reference, and wait on cond_take
            X = get_arraychannel(id)
            wait(X.cond_take)
        end
        remotecall_wait(send_to, id, place) do id, payload
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

function serialize(S::AbstractSerializer, ac::ArrayChannel)
    writetag(S.io, OBJECT_TAG)
    serialize(S, typeof(ac))
    serialize(S, ac.rrid)
end

function deserialize(S::AbstractSerializer, t::Type{<:ArrayChannel}) where {T,N}
    id = deserialize(S) :: RRID
    ch = ac_get_from(id)
    if ch ≠ nothing
        return ch
    end
    return ArrayChannel(id)
end

# Required to show InPlaceArray objects
function show(S::IO, ac::ArrayChannel)
    if ac.buffer == nothing
        return
    end
	invoke(show, Tuple{IO, InPlaceArray}, S, ac.buffer::InPlaceArray)
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

# Rohan McLure, 2018

"""
Channel construct with getindex, setindex! overrides. Implements an array construct that may be 'committed' for synchronisation with any number of distributed workers after acknowledging a 'take!' from the recipients.
"""
mutable struct ArrayChannel
    lock::ReentrantLock
    cond_take::Event
    cond_put::Event
    buffer::Union{Nothing, InPlaceArray}
    scratch1::Union{Nothing, InPlaceArray}
    scratch2::Union{Nothing, InPlaceArray}
    participants::Union{Nothing, Vector{Int64}}
    rrid::RRID

    # Null constructor
    function ArrayChannel(id::RRID)
        ch = new(ReentrantLock(), Event(), Event(), nothing, nothing, nothing, nothing, id)
        channels[id] = ch
        return ch
    end

    # Headless constructor
    function ArrayChannel(A::InPlaceArray{T,N}, ps::Vector{Int64}, id::RRID, s1=nothing, s2=nothing) where {T,N}
        ps = sort(ps)
        ch = new(ReentrantLock(), Event(), Event(), A, s1, s2, ps, id)
        channels[id] = ch
        return ch
    end

    # Main constructor
    function ArrayChannel(T::Type, participants::Vector{Int64}, dims...)
        id = RRID()
        participants = sort(participants)
        ch = new(ReentrantLock(), Event(), Event(), nothing, nothing, nothing, participants, id)
        @sync for proc in participants
            if proc == myid()
                @async begin
                    ipa = InPlaceArray(Array{T}(undef, dims...), id)
                    s1 = InPlaceArray(Array{T}(undef, dims...), id, 1)
                    s2 = InPlaceArray(Array{T}(undef, dims...), id, 2)
                    ch.buffer = ipa
                    ch.scratch1 = s1
                    ch.scratch2 = s2
                    channels[id] = ch
                end
            else
                @spawnat proc begin
                    ipa = InPlaceArray(Array{T}(undef, dims...), id)
                    s1 = InPlaceArray(Array{T}(undef, dims...), id, 1)
                    s2 = InPlaceArray(Array{T}(undef, dims...), id, 2)
                    ArrayChannel(ipa, participants, id, s1, s2)
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

"""
Participate in a reduction on all processes participating in this ArrayChannel, where only the 'root' while be affected by the result.

Blocks until this process' role in the reduction is complete.
"""
function reduce!(op, ac::ArrayChannel, root::Int64)
    lock(ac.lock) do
        peers = ac.participants
        n = length(peers)
        pow_2 = 2^Int(ceil(log(2,n))) # Smallest power of two ≤
        idx = indexin(myid(), peers)[1]
        root_idx = indexin(root, peers)[1]
        # Reshape around root
        pos = (idx < root_idx ? pow_2 - n : pow_2) - (idx - root_idx)
        z = pos
        lowest_z = pow_2 - n + 1
        k = 0
        leaf = z % 2 != 0 || z == lowest_z
        while z % 2 == 0
            if pos - 2^k >= lowest_z
               wait(ac.cond_put)
                # Clear
                ac.cond_put.set = false

                # Perform computation
                acc_buffer = myid() == root ? ac.buffer : ac.scratch1
                if k == 0
                    broadcast!(op, acc_buffer, ac.buffer, ac.scratch2)
                else
                    broadcast!(op, acc_buffer, acc_buffer, ac.scratch2)
                end
            end
            z ÷= 2
            k += 1
        end

        if myid() != root
            sender_idx = mod(idx - 2^k, n)
            sender_idx = sender_idx == 0 ? n : sender_idx
            send_to = peers[sender_idx]
            if leaf
                target(ac.buffer, send_to, 2)
            else
                target(ac.scratch1, send_to, 2)
            end
        end
    end
end

function target(ipa::InPlaceArray{T,N}, proc_id::Int64, buf::Int64) where {T,N}
    temp = ipa.buf_no
    ipa.buf_no = buf
    remotecall_wait(proc_id, ipa) do place
        X = get_arraychannel(place.rrid)
        notify(X.cond_put)
    end
    ipa.buf_no = temp
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

function fill!(ac::ArrayChannel, v)
    fill!(ac.buffer.src, v)
end

function ac_get_from(id::RRID)
    if id in keys(channels)
        return channels[id]
    end
    nothing
end

global channels = Dict{RRID, ArrayChannel}()

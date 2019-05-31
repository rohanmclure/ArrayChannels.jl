# Rohan McLure 2019 (C), Australian National University, licensed under MIT.

"""
Construct permitting synchronisation to be occuring simultaneously with a number of different processing preparing to wrote to our local array.
"""
mutable struct Handshake
    pid_events::Vector{Union{Channel{Nothing}, Nothing}}

    function Handshake(participants::Vector{Int64})
        events = map(1:nprocs()) do pid
            if pid in participants
                return Channel{Nothing}(0)
            else
                return nothing
            end
        end
        new(events)
    end
end

"""
    put!(hs::Handshake, put_as::Int64)

Synchronisation primatives for custom synchronisation type.
"""
function put!(hs::Handshake, put_as::Int64)
    put!(hs.pid_events[put_as], nothing)
end

"""
    take!(hs::Handshake, take_from::Int64)

Synchronisation primatives for custom synchronisation type.
"""
function take!(hs::Handshake, take_from::Int64)
    take!(hs.pid_events[take_from])
end

"""
    ArrayChannel(T::Type, participants::Vector{Int64}, dims::Int64...)

Channel construct that associates itself with an array at each of the specified 'participating' processes.
Allows for synchronous, in place communication between bufferes on different processes by means of [`put!`](@ref), [`take!`](@ref), [scatter!](@ref), [gather!](@ref) or [reduce!](@ref).

# Examples
```jldoctest
julia> A = ArrayChannel(Float64, workers(), 2, 2)

Nothing displayed as master process is not part of workers(), and as such
does not host any local data.
```

"""
mutable struct ArrayChannel
    lock::Union{Nothing, ReentrantLock}
    cond_take::Union{Nothing, Handshake}
    cond_put::Union{Nothing, Channel{Nothing}}
    buffer::Union{Nothing, InPlaceArray}
    scratch1::Union{Nothing, InPlaceArray}
    scratch2::Union{Nothing, InPlaceArray}
    participants::Union{Nothing, Vector{Int64}}
    rrid::RRID

    # Null constructor
    function ArrayChannel(id::RRID)
        ch = new(nothing, nothing, nothing, nothing, nothing, nothing, nothing, id)
        channels[id] = ch
        return ch
    end

    # Headless constructor
    function ArrayChannel(A::InPlaceArray{T,N}, ps::Vector{Int64}, id::RRID, s1=nothing, s2=nothing) where {T,N}
        ps = sort(ps)
        ch = new(ReentrantLock(), Handshake(ps), Channel{Nothing}(1), A, s1, s2, ps, id)
        channels[id] = ch
        return ch
    end

    # Main constructor
    function ArrayChannel(T::Type, participants::Vector{Int64}, dims...)
        id = RRID()
        participants = sort(participants)
        ch = new(ReentrantLock(), Handshake(participants), Channel{Nothing}(1), nothing, nothing, nothing, participants, id)
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
    put!(ac::ArrayChannel, send_to::Int64, [tag::Union{Distributed.RRID, Nothing}])

put! initiates two blocking remotecalls for each worker in the workerpool. The first waits on the receiver to authorises the buffer to be overwritten, the second writes the data.
"""
function put!(ac::ArrayChannel, send_to::Int64, tag::Union{RRID, Nothing}=nothing)
    same_channel = tag === nothing
    lock(ac.lock) do
        id = same_channel ? ac.rrid : (tag::RRID)
        place = ac.buffer
        remotecall_wait(send_to, id, myid()) do rrid, my_pid
            # From the rrid, get the ArrayChannel reference, and wait on cond_take
            X = get_arraychannel(rrid)
            put!(X.cond_take, my_pid)
        end
        if same_channel
            remotecall_wait(send_to, id, place) do id, payload
                # Serialise the InPlaceArray, but do nothing with it.
                X = get_arraychannel(id)
                put!(X.cond_put, nothing)
            end
        else
            # Target another channel's buffer by anonymously altering the buffer metadata
            target(place, send_to, 0, tag)
        end
    end
end

"""
    take!(ac::ArrayChannel, recv_from::Int64)

take! signals to the other owners of the ArrayChannel the intention to overwrite the buffer with new array data, and then waits for it to be written.
"""
function take!(ac::ArrayChannel, recv_from::Int64)
    # Accept any code
    take!(ac.cond_take, recv_from)
    lock(ac.lock) do
        take!(ac.cond_put)
    end
    return ac
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
    reduce!(op, ac::ArrayChannel, root::Int64)
Participate in a reduction on all processes participating in this ArrayChannel, where only the 'root' while be affected by the result.

Blocks until this process' role in the reduction is complete.

# Example
```jldoctest
Reduce by taking the vector sum, with root at process one
julia> reduce!(+, A, 1)
```
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
                take!(ac.cond_put)

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

"""
Since InPlaceArrays are serialised in place (subject to their buffer reference), use this method to anonymously alter the buffer reference before sendint to a buffer of choice.

Buffers are counted as follows:
The reference to the main buffer for the ArrayChannel is given a code zero.
Currently only to scratch buffers are needed for `reduce!`, however a positive integer will reference these.
"""
function target(ipa::InPlaceArray{T,N}, proc_id::Int64, buf::Int64, channel::Union{RRID, Nothing}=nothing) where {T,N}
    new_id = channel === nothing ? ipa.rrid : (channel::RRID)
    backup_id = ipa.rrid
    backup_buf_no = ipa.buf_no
    ipa.buf_no = buf
    ipa.rrid = new_id
    remotecall_wait(proc_id, ipa) do place
        X = get_arraychannel(place.rrid)
        put!(X.cond_put, nothing)
    end
    ipa.buf_no = backup_buf_no
    ipa.rrid = backup_id
end

# Required to show InPlaceArray objects
function show(S::IO, ac::ArrayChannel)
    if ac.buffer == nothing
        return
    end
	invoke(show, Tuple{IO, InPlaceArray}, S, ac.buffer::InPlaceArray)
end

function copy!(AC::ArrayChannel, src::AbstractArray)
    copy!(AC.buffer.src, src)
end

function copy!(dest::AbstractArray, AC::ArrayChannel)
    copy!(dest, AC.buffer.src)
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

function length(ac::ArrayChannel)
    length(ac.buffer.src)
end

function iterate(ac::ArrayChannel)
    iterate(ac.buffer.src)
end

function iterate(ac::ArrayChannel, state)
    iterate(ac.buffer.src)
end

function broadcast(op, As::ArrayChannel...)
    broadcast(op, map(x->x.buffer.src, As))
end

function broadcast!(op, dest::ArrayChannel, As::AbstractArray...)
    broadcast!(op, dest.buffer.src, As)
end

function broadcast!(op, dest::AbstractArray, As::ArrayChannel...)
    broadcast!(op, dest, map(x->x.buffer.src, As))
end

function ac_get_from(id::RRID)
    if id in keys(channels)
        return channels[id]
    end
    nothing
end

global channels = Dict{RRID, ArrayChannel}()

# Rohan McLure 2019 (C), Australian National University, licensed under MIT.
# Import me using @everywhere - we will later permit changing of workerpools

using Distributed
import Distributed: RRID, WorkerPool

using Serialization
using Serialization: AbstractSerializer, serialize, deserialize, serialize_cycle_header, serialize_type, writetag, deserialize_fillarray!
import Serialization: serialize, deserialize

import Base: size, show, getindex

# Serialisation / Deserialisation of InPlaceArrays will involve a deep copy to a preallocated buffer
mutable struct InPlaceArray{T,N} <: DenseArray{T,N}
    src :: Array{T,N} # Reference to array, never overwritten.
    rrid :: RRID

    # Headless constructor. Returned by the output of an inplacearray.
    function InPlaceArray{T,N}(A::Array{T,N}, id::RRID) where {T,N}
        new(A, id)::InPlaceArray{T,N}
    end

	function InPlaceArray{T,N}(A::Array{T,N}) where {T,N}
        out = new(A, RRID()) # Need this to associate with the InPlaceArray
		@sync for proc in workers()
            if proc != myid()
    			@async remotecall_wait(proc, out.rrid, size(out), T) do reference, dims, T
    				buffers[reference] = Array{T}(undef, dims...) # May instead point to the array.
    			end
            else
                @async buffers[reference] = out.src
            end
		end
        out::InPlaceArray{T,N}
    end
end

# Required to show InPlaceArray objects
function show(S::IO, A::InPlaceArray)
	invoke(show, Tuple{IO, DenseArray}, S, A.src::Array)
end

function show(S::IO, mime::MIME"text/plain", A::InPlaceArray)
    invoke(show, Tuple{IO, MIME"text/plain", DenseArray}, S, MIME"text/plain"(), A.src)
end

function getindex(I::InPlaceArray, keys...)
    getindex(I.src, keys...)
end

function size(A::InPlaceArray)
    size(A.src)
end

function get_from(RRID::RRID, worker)
    return @fetchfrom worker buffers[RRID]
end

function serialize(S::AbstractSerializer, A::InPlaceArray)
    @assert A isa InPlaceArray

    writetag(S.io, Serialization.OBJECT_TAG)
    serialize(S, typeof(A))
    # Serialise the rrid before the payload array
    serialize(S, A.rrid)
    serialize(S, A.src)
end

function deserialize(S::AbstractSerializer, t::Type{<:InPlaceArray{T,N}}) where {T,N}
    # Remote reference which references this 'array' uniquely
    id = deserialize(S)     :: RRID

    # Read the object tag for the array. Forces following lines to deserialise components of array,
    # rather than full array. We need this for granular control.
    read(S.io, UInt8)::UInt8

    # Deserialise an array but pop it in place
    slot = S.counter; S.counter += 1
    d1 = deserialize(S)
    if isa(d1, Type)
        elty = d1
        d1 = deserialize(S)
    else
        elty = UInt8
    end
    if isa(d1, Integer)
        if elty !== Bool && isbitstype(elty)
            a = Vector{elty}(undef, d1)
            S.table[slot] = a
            return read!(S.io, a)
        end
        dims = (Int(d1),)
    else
        dims = convert(Dims, d1)::Dims
    end
    local A
    if isbitstype(elty)
        n = prod(dims)::Int
        if elty === Bool && n > 0
            A = buffers[id]
            # A = Array{Bool, length(dims)}(undef, dims)
            i = 1
            while i <= n
                b = read(S.io, UInt8)::UInt8
                v = (b >> 7) != 0
                count = b & 0x7f
                nxt = i + count
                while i < nxt
                    A[i] = v
                    i += 1
                end
            end
        else
            A = read!(S.io, buffers[id])
        end
        S.table[slot] = A
    else
        # A = Array{elty, length(dims)}(undef, dims)
        A = buffers[id]
        S.table[slot] = A
        # sizehint!(S.table, S.counter + div(length(A),4)) # I reckon not necessary
        deserialize_fillarray!(A, S)
    end

    return InPlaceArray(A::Array{T,N}, id)
end

InPlaceArray(A::Array{T,N}) where {T,N} = InPlaceArray{T,N}(A)
InPlaceArray(A::Array{T,N}, id::RRID) where {T,N} = InPlaceArray{T,N}(A, id)

global buffers = Dict{RRID, Array}()

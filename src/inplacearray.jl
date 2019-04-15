# Rohan McLure 2019 (C), Australian National University, licensed under MIT.

# Serialisation / Deserialisation of InPlaceArrays will involve a deep copy to a preallocated buffer
mutable struct InPlaceArray{T,N} <: DenseArray{T,N}
    src :: Array{T,N} # Reference to array, never overwritten.
    rrid :: RRID

    function InPlaceArray{T,N}(A::Array{T,N}, id::RRID) where {T,N}
        ipa = new(A, id)::InPlaceArray{T,N}
        places[id] = A
        return ipa
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

function serialize(S::AbstractSerializer, A::InPlaceArray)
    writetag(S.io, OBJECT_TAG)
    serialize(S, typeof(A))
    serialize(S, A.rrid)
    serialize(S, A.src)
end

function deserialize(S::AbstractSerializer, t::Type{<:InPlaceArray{T,N}}) where {T,N}
    # Remote reference which references this 'array' uniquely
    id = deserialize(S)     :: RRID

    # Read the object tag for the array. Forces following lines to deserialise components of array,
    # rather than full array. We need this for granular control.
    read(S.io, UInt8)::UInt8

    return deserialize_helper(id, S, places[id])
end

function deserialize_helper(id::RRID, S::AbstractSerializer, A::Array{T,N}) where {T,N}
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
            S.table[slot] = A
            return read!(S.io, A)
        end
        dims = (Int(d1),)
    else
        dims = convert(Dims, d1)::Dims
    end
    if isbitstype(elty)
        n = prod(dims)::Int
        if elty === Bool && n > 0
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
            read!(S.io, A)
        end
        S.table[slot] = A
    else
        S.table[slot] = A
        # sizehint!(S.table, S.counter + div(length(A),4)) # I reckon not necessary
        deserialize_fillarray!(A, S)
    end
    return InPlaceArray(A::Array{T,N}, id)
end

InPlaceArray(A::Array{T,N}) where {T,N} = InPlaceArray{T,N}(A)
InPlaceArray(A::Array{T,N}, id::RRID) where {T,N} = InPlaceArray{T,N}(A, id)

global places = Dict{RRID, Array}()

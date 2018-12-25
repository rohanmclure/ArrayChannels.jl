# Rohan McLure 2019 (C), Australian National University, licensed under MIT.
# Import me using @everywhere - we will later permit changing of workerpools

using Distributed
import Distributed: RRID, WorkerPool

using Serialization
using Serialization: AbstractSerializer, serialize, deserialize
import Serialization: serialize, deserialize

import Base: size, show, getindex

# Serialisation / Deserialisation of InPlaceArrays will involve a deep copy to a preallocated buffer

mutable struct InPlaceArray{T,N} <: DenseArray{T,N}
    src :: Array{T,N} # Reference to array, never overwritten.
    rrid :: RRID

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

function getindex(I::InPlaceArray, key...)
    println("Debugging this boii")
    getindex(I.src, key...)
end

function size(A::InPlaceArray)
    size(A.src)
end

function get_from(RRID::RRID, worker)
    return @fetchfrom worker buffers[RRID]
end

function serialize(s::AbstractSerializer, t::InPlaceArray)
    println("Lol we got there")
end

function deserialize(s::AbstractSerializer, t::Type{<:InPlaceArray})
    println("Yeah boiii!")
    invoke(deserialize, Tuple{AbstractSerializer, DataType}, s,t)terminal
end

# InPlaceArray{T}(A::Array{T,1}) where {T} = InPlaceArray{T,1}(A)
# InPlaceArray{T}(A::Array{T,2}) where {T} = InPlaceArray{T,2}(A)

InPlaceArray(A::Array{T,N}) where {T,N} = InPlaceArray{T,N}(A)

global buffers = Dict{RRID, Array}()

using Distributed
import Distributed: RRID, WorkerPool

using Serialization
using Serialization: AbstractSerializer, serialize, deserialize
import Serialization: serialize, deserialize

mutable struct InPlaceArray{T,N} <: DenseArray{T,N}
    src :: Array{T,N} # Reference to array, never overwritten.
    rrid :: RRID

	function InPlaceArray{T,N}(A::Array{T,N}) where {T,N}
		out = new(A, RRID()) # Need this to associate with the InPlaceArray
		@sync for proc in workers()
			@async remotecall_wait(proc, out.rrid, out.src) do reference, payload
				buffers[reference] = payload # May instead point to the array.
			end
		end
        out::InPlaceArray{T,N}
    end
end

InPlaceArray{T}(A::Array{T,1}) where {T} = InPlaceArray{T,1}(A)
InPlaceArray{T}(A::Array{T,2}) where {T} = InPlaceArray{T,2}(A)

InPlaceArray(A::Array{T,N}) where {T,N} = InPlaceArray{T,N}(A)

global buffers = Dict{RRID, Array}()

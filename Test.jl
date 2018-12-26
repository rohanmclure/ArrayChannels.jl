using Distributed

using Serialization
using Serialization: AbstractSerializer, serialize, deserialize, serialize_cycle_header, serialize_type, writetag
import Serialization: serialize, deserialize

import Base: size, show, getindex

mutable struct Custom
    send_me :: Int
    dont_send_me :: Union{Int, Nothing}

    function Custom(x,y)
        new(x,y)
    end
end

function serialize(S::AbstractSerializer, C::Custom)
    writetag(S.io, Serialization.OBJECT_TAG)
    serialize(S, typeof(C)) # Serialize the actual type object
    serialize(S, C.send_me)
end

function deserialize(S::AbstractSerializer, t::Type{<:Custom})
    x = deserialize(S)
    Custom(x, nothing)
end

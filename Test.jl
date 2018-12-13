using Distributed
addprocs(4)
@sync @everywhere using Serialization: AbstractSerializer, serialize, deserialize
@sync @everywhere import Serialization: serialize, deserialize

@everywhere mutable struct Custom
    x :: Int

    function Custom()
        new(5::Int)
    end
end

@everywhere function deserialize(s::AbstractSerializer, t::Type{<:Custom})
    println("Yeah boiii!")
    invoke(deserialize, Tuple{AbstractSerializer, DataType}, s,t)
end

rc = @fetchfrom 2 global c = RemoteChannel(()->Channel{Custom}(1))
val = Custom()

put!(rc,val)
println(take!(rc).x)

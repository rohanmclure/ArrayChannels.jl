using Distributed
addprocs(1)
@everywhere include("arraychannels.jl")

X = ArrayChannel(Float64, 2,2)
println(X)

X[1,1] = 2.0; X[2,2] = 4.0

println(X)

X[1,2] = 0.0; X[2,1] = 0.0
put!(X)
id = X.rrid

function get_arraychannel(proc,id)
    function do_reference()
        references[id]
    return @fetchfrom proc do_reference[id]

@assert !(get_arraychannel(2,id) == X)

using Distributed
addprocs(1)
@everywhere include("arraychannels.jl")

X = ArrayChannel(Float64, 2,2)
println(X)

X[1,1] = 2.0; X[2,2] = 4.0

println(X)

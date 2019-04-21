# using Test
using Distributed
# import Distributed: RRID, workerpool

include("arraychannels_test.jl")
test_serialise()
include("interleave_test.jl")
test_interleave()
include("reduce_test.jl")
test_reduce_two()
test_reduce_five()

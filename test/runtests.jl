using Test
using Distributed
import Distributed: RRID, workerpool

include("arraychannels_test.jl")

test_put_take_init()

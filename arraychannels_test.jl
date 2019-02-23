using Distributed
addprocs(1)
@everywhere using Test
@everywhere include("arraychannels.jl")
@everywhere function do_reference(i)
    channels[i]
end

X = ArrayChannel(Float64, 2,2)
B = copy(X.buffer.src)
X[1,1] = 2.0; X[2,2] = 4.0
X[1,2] = 0.0; X[2,1] = 0.0
rrid = X.rrid

A = [2.0 0.0; 0.0 4.0]
# Test for no deadlocks
@sync for x in 1:100
    @async put!(X)
    @async begin
        remotecall_wait(2, rrid) do id
            take!(do_reference(id))
        end
    end
end

# After a put the array remains unchanged
@test A == X.buffer.src

id = X.rrid

# Don't point to the same array
Y = remotecall_fetch(do_reference, 2, id)

@test Y.buffer.src  == X.buffer.src == A
@test Y !== X

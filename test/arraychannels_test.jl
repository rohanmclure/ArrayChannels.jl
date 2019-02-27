addprocs(1); @assert nprocs() == 2
@everywhere using Test
@everywhere using ArrayChannels

function test_put_take_init()
    @testset "Test ArrayChannel Logistics:" begin
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
                    take!(ac_get_from(id))
                end
            end
            println("Waiting to put!, take!")
        end
        println("Completed put!, take!")

        # After a put the array remains unchanged
        @test A == X.buffer.src

        id = X.rrid

        # Don't point to the same array
        Y = remotecall_fetch(ac_get_from, 2, id)

        @test Y.buffer.src  == X.buffer.src == A
        @test Y !== X
    end
end

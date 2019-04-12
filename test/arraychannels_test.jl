rmprocs(workers()...); addprocs(2); @assert nprocs() == 3
@everywhere using Test
@everywhere using ArrayChannels

function test_serialise()
    @testset "ArrayChannel Serialisation" begin
        X = ArrayChannel(Float64, 2, 2)
        X[1,1] = 2.0; X[2,2] = 4.0

        id = X.rrid

        @sync begin
            @async put!(X,[2])
            @async remotecall_wait(2, id) do id
                take!(ac_get_from(id))
                nothing
            end
        end

        @test (@fetchfrom 2 ac_get_from(id)[1,1]) == 2.0
    end
end

function test_put_take_init()
    @testset "Test ArrayChannel Logistics:" begin
        X = ArrayChannel(Float64, 2,2)
        B = copy(X.buffer.src)
        X[1,1] = 2.0; X[2,2] = 4.0
        X[1,2] = 0.0; X[2,1] = 0.0
        rrid = X.rrid

        A = [2.0 0.0; 0.0 4.0]

        D = remotecall_fetch(2, rrid) do id
            Z = ac_get_from(id)
            return (Z[1,1], Z[2,2])
        end

        println(D)

        # Test for no deadlocks
        @sync for x in 1:100
            @async put!(X)
            @async begin
                remotecall_wait(2, rrid) do id
                    take!(ac_get_from(id))
                end
            end
        end

        # After a put the array remains unchanged
        @test A == X.buffer.src

        id = X.rrid

        # Don't point to the same array
        Y = remotecall_fetch(ac_get_from, 2, id)

        @test Y.buffer.src  == X.buffer.src == A
        @test Y !== X

        # Test that components successfully serialised.
        D = remotecall_fetch(2, id) do id
            Z = ac_get_from(id)
            return (Z[1,1], Z[2,2])
        end
        println("Check that serialised correctly")
        @test D == (2.0, 4.0)
    end
end

rmprocs(workers()...); addprocs(2); @assert nprocs() == 3
using Test
@everywhere using ArrayChannels

function test_serialise()
    @testset "ArrayChannel Serialisation" begin
        X = ArrayChannel(Float64, procs(), 2, 2)
        X[1,1] = 2.0; X[2,2] = 4.0

        id = X.rrid

        @sync begin
            @async put!(X, 2)
            @async @spawnat 2 take!(X, 1)
        end

        @test (@fetchfrom 2 X[1,1]) == 2.0
    end
end

function test_synchronisation()
    @testset "Test synchronisation by put!, take!" begin
        X = ArrayChannel(Int64, [1,2], 100000)
        T = Vector{Future}(undef, 5)
        @sync for i in 1:5
            T[i] = @spawnat 2 begin
                take!(X, 1)
                return X[1]
            end
            fill!(X, i)
            put!(X, 2)
        end
        for (i, t) in enumerate(T)
            @test fetch(t) == i
        end
    end
end

function test_target_other_channel()
    @testset "Target another channel with put!" begin
        X = ArrayChannel(Int64, [1,2], 10)
        Y = ArrayChannel(Int64, [1,2], 10)

        fill!(X, 10)
        @sync @spawnat 2 fill!(Y, 20)

        local test_value
        @sync begin
            @async put!(X, 2, Y.rrid)
            test_value = @spawnat 2 begin
                take!(Y, 1)
                Y[1,1]
            end
        end
        @test fetch(test_value) == 10
    end
end

function test_put_take_init()
    @testset "Test ArrayChannel Logistics:" begin
        X = ArrayChannel(Float64, procs(), 2, 2)
        B = copy(X.buffer.src)
        X[1,1] = 2.0; X[2,2] = 4.0
        X[1,2] = 0.0; X[2,1] = 0.0
        rrid = X.rrid

        A = [2.0 0.0; 0.0 4.0]

        D = remotecall_fetch(2, rrid) do id
            Z = ac_get_from(id)
            return (Z[1,1], Z[2,2])
        end

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
        @test D == (2.0, 4.0)
    end
end

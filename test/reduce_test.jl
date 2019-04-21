rmprocs(workers()...); addprocs(4); @assert nprocs() == 5
@everywhere using ArrayChannels
using Test

function test_reduce_two()
    @testset "Two-process Reduction" begin
        A = ArrayChannel(Float64, procs()[1:2], 10)
        fill!(A, 1.0)
        proc_2 = procs()[2]
        @sync @spawnat proc_2 fill!(A, 1.0)
        @sync begin
            @async reduce!(+, A, 1)
            @spawnat proc_2 reduce!(+, A, 1)
        end
        @test A[1] == 2.0

        @sync begin
            @async reduce!(+, A, proc_2)
            @spawnat proc_2 reduce!(+, A, proc_2)
        end
        @test (@fetchfrom proc_2 A[1]) == 3.0
    end
end

function test_reduce_five()
    @testset "Five-process reduction" begin
        A = ArrayChannel(Float64, procs(), 10)
        @sync for i in 1 : length(procs())
            @spawnat procs()[i] fill!(A, i)
        end
        proc_3 = procs()[3]
        @sync for proc in procs()
            @spawnat proc reduce!(+, A, proc_3)
        end
        @test (@fetchfrom proc_3 A[1]) == 15.0
    end
end

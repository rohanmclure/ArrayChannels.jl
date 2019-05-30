rmprocs(workers()...); addprocs(2); @assert nprocs() == 3
@everywhere using Test
@everywhere using ArrayChannels

function test_interleave()
   @testset "Order Maintained" begin
        A = ArrayChannel(Float64, procs(), 2, 2)
        pid = myid()
        id = A.rrid
        local remote
        @sync begin
            for i in 1:10
                @async begin
                    A[1,1] = i
                    put!(A, procs()[2])
                end
            end

            remote = @async remotecall_fetch(procs()[2], id) do rrid
                X = ac_get_from(rrid)
                v = Vector{Int64}()
                for i in 1:10
                    take!(X, pid)
                    push!(v, i)
                end
                return v
            end
        end
        for i in 1:10
           @test remote.result[i] == i
        end
   end
end

using Distributed
addprocs(2)

@everywhere using Test

@everywhere function lookup(id)
    return places[id]
end

@everywhere function exists(id)
    try
        places[id]
    catch KeyError
        return false
    end
    return true
end

function test_serialisation(A)
    X = InPlaceArray(A)
    id = X.rrid
    @fetchfrom 2 X

    remotecall_wait(2,id) do rrid
        @test exists(rrid)
    end

    A = remotecall_fetch(2,X,id) do IA, rrid
        return lookup(rrid)
    end

    @test X == A
end

# Floating point test?
test_serialisation([1 2; 3 4; 5 6])
test_serialisation([1.0 2.0; 3.0 4.0; 5.0 6.0])

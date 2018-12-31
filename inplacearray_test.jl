@everywhere include("inplacearray.jl")

<<<<<<< HEAD
X = InPlaceArray([1 2; 3 4; 5 6])

@fetchfrom 2 X
=======
@everywhere function lookup(id)
    return buffers[id]
end

@everywhere function exists(id)
    try
        buffers[id]
    catch KeyError
        return true
    end
    return false
end

X = InPlaceArray([1 2; 3 4; 5 6])
id = X.rrid
@fetchfrom 2 X

remotecall_wait(2,id) do rrid
    @assert !exists(rrid)
end

A = remotecall_fetch(2,X,id) do IA, rrid
    return lookup(rrid)
end

# Got the saved copy of the InPlaceArray
println(A)
>>>>>>> no-allocate

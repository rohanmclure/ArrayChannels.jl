@everywhere include("inplacearray.jl")

X = InPlaceArray([1 2; 3 4; 5 6])

@fetchfrom 2 X

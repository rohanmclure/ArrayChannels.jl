@everywhere include("Test.jl")

X = Custom([10,15],20)

writer = IOBuffer()
println(typeof(writer))
serialize(writer, X)
seekstart(writer)
encoding = read(writer)

reader = IOBuffer(encoding)
Y = deserialize(reader)
println(Y)

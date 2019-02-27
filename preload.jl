using Distributed
addprocs(1)
@everywhere using Pkg
@everywhere Pkg.activate(".")
@everywhere Pkg.add(["Distributed", "Serialization"])
Pkg.test()
@everywhere using ArrayChannels

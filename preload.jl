using Distributed
addprocs(2)
@everywhere using Pkg
@everywhere Pkg.activate(".")
@everywhere Pkg.add(["Distributed", "Serialization", "Sockets"])
@everywhere Pkg.resolve()
Pkg.test()
@everywhere using ArrayChannels

using Distributed

@everywhere using Pkg
@everywhere Pkg.activate(".")
@everywhere Pkg.add(["Distributed", "Serialization", "Sockets"])
Pkg.resolve()
# Pkg.test()

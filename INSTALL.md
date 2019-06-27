# Installation

From a Julia REPL in this directory:

```julia
Pkg> activate .
(ArrayChannels) Pkg> add Distributed
(ArrayChannels) Pkg> add Serialization
(ArrayChannels) Pkg> add Sockets
(ArrayChannels) Pkg> resolve
(ArrayChannels) Pkg> dev .
```

`ArrayChannels.jl` is now importable through:

```julia
julia> using ArrayChannels
```

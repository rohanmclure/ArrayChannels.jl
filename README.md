[![Binder](https://mybinder.org/badge_logo.svg)](https://mybinder.org/v2/gh/rohanmclure/ArrayChannels.jl/master)

# ArrayChannels.jl

## Cache Locality

Library which encapsulates an `AbstractArray`, and providing synchronous communication of arrays that occurs _in-place_, i.e. the same local array on each participating process will be used for every communication. This behaviour differs slightly from the default behaviour for Julia `RemoteChannel` constructs, which causes a new array to be allocated for every communication action.

This allows for increased cache locality on distributed workloads. Using `RemoteChannels` or `remotecall` primatives, if data must be distributed between processes within a tight loop, then each individual iteration of the loop will cause the allocation of a new array. Instead, `ArrayChannels` will allocate a local array at each participating process, and then permit the user to reuse the array for a number of parallelism patterns.

## Running

During development, `ArrayChannels` may be imported by directly cloning this repository, and then using `Pkg` to stage the local repository for development.

```sh
> git clone git@github.com:rohanmclure/ArrayChannels.jl.git ArrayChannels
> julia
julia> ]
Pkg> activate ./ArrayChannels
Pkg> resolve
> julia
julia> ]
Pkg> add Distributed Serialization Sockets
Pkg> dev ./ArrayChannels
```

To run the package tests, simply use the following after installation:

```sh
julia> ]
Pkg> test ArrayChannels
```

Afterwards, you may import `ArrayChannels` on all processes by running `@everywhere using ArrayChannels`.

To test the package, simply use the interface provided in `Pkg`.

```sh
> julia
julia> ]
Pkg> test ArrayChannels
```

Alternatively, you may build the Docker image and create a container instance for a Jupyter environment.

```sh
docker build . -t arraychannels
docker run -p 0.0.0.0:8888:8888 --rm -it arraychannels jupyter notebook --ip=0.0.0.0 --port=8888
```

## Supported Patterns

### Send / Receive

The most essential pattern is the synchronous send / receive pattern. It takes the form of two function calls, `put!` and `take!`. Once we have written to an array, we may update the contents of all local arrays at participating processes via a pair of `put!` and `take!` operations.

```julia
@everywhere using ArrayChannels
# Initialise a two by two ArrayChannel at each process
A = ArrayChannel(Float64, procs(), 2, 2)
B = [2.0 0.0;
     0.0 4.0]

copy!(A,B)

# Print the contents of A at locale 2
# The contents of the ArrayChannel at 2 will be uninitialised
println(@fetchfrom 2 A)

@sync begin
    # Blocking put! to process 1
    @async put!(A, 2)
    # Blocking take! from process 1
    @spawnat 2 take!(A, 1)
end
```

While the local array duplication of `A` at process two began unitialised, performing matching `put!` and `take!` operations causes A's contents to be updated at process 2.

Where dimensions match, the sending process may elect to specify the output channel by using the global reference identifier of the destination channel:

```julia
@everywhere using ArrayChannels
# From process one
A = ArrayChannel(Float64, [1,2], 10, 2)
B = ArrayChannel(Float64, [1,2], 10, 2)
target_rrid = B.rrid

@sync begin
    @async put!(A, 2, target_rrid)
    @spawnat 2 take!(B, 1)
end
```

This features is less often used, but allows for processes to directly reference the destination buffer for their message.

### Reduce

The `reduce!` function accepts a binary operator, the channel with which you would like to perform the reduction, and the id of the root process for the reduction. All processes that participate in an ArrayChannel must call `reduce!` for the reduction to complete. `reduce!` is blocking while a process is waiting on another process' data.

```julia
@everywhere using ArrayChannels
# Assume myid() = 1
A = ArrayChannel(Int64, [1,2,3,4], 10)

@sync for proc in [1,2,3,4]
    @spawnat proc fill!(A, 1)
end

@sync for proc in [1,2,3,4]
    @spawnat proc reduce!(+, A, 1)
end
@assert A[1] == 4
```

### Scatter / Gather

The `scatter!` and `gather!` patterns are not yet completed, but allow for in-place distribution of array data even to processes that do not participate in the underlying `ArrayChannel`.

## Library Structure

### InPlaceArray

Essentially all functions that operate on `ArrayChannel` objects serve as a wrapper to one or more `InPlaceArray` objects.
`InPlaceArray` objects encapsulate a Julia `DenseArray`, with the only additional functionality being in that they override the `serialize` and `deserialize` bindings for arrays. Essentially, `InPlaceArray` objects are identified by a remote reference id, and when received by the target process, will be deposited in a designated spot for that `InPlaceArray`.

### ArrayChannels

The `arraychannels.jl` file provides a data type known as the `ArrayChannel` and some synchronisation constructs that provide a synchronous interface to one or more `InPlaceArray` objects.

## Benchmark code

We provide a number of different benchmarks for `ArrayChannels.jl`, including a simple, two-process ping-pong, as well as three of the Intel PRK. Reference versions of the PRK, written in MPI are available [here](https://www.github.com/parres/kernels/tree/master/MPI1/), and provide a good performance comparison.

# ArrayChannels.jl

## Cache Locality

Library which encapsulates an `AbstractArray`, and provides `put!` and `take!` methods for synchronous communication of the Array. Most importantly, communication of arrays will occur _in-place_, i.e. the same local array on each participating process will be used for every communication. This behaviour differs slightly from the default behaviour for Julia `RemoteChannel` constructs, which causes a new array to be allocated for every communication action.

This allows for increased cache locality on distributed workloads. Using `RemoteChannels` or `remotecall` primatives, if data must be distributed between processes within a tight loop, then each individual iteration of the loop will cause the allocation of a new array. Instead, `ArrayChannels` will allocate a local array at each participating process, and then permit the user to reuse the array for a number of parallelism patterns.

## Running

During development, you may use `julia --load preload.jl` to experiment with the ArrayChannels.jl library. This will precompile dependencies and provide a two-process environment for experimenation.

## Supported Patterns

### Synchronisaiton patterns

The most essential pattern is the overwrite pattern. It takes the form of two function calls, `put!` and `take!`. Once we have written to an array, we may update the contents of all local arrays at participating processes via a pair of `put!` and `take!` operations.

```julia
using Distributed
addprocs(1)
@everywhere using ArrayChannels

A = ArrayChannel(Float64, 2, 2)
B = [2.0 0.0;
     0.0 4.0]

copyto!(A,B)

id = A.rrid
println(id)

## RRID()

println(@fetchfrom 2 ac_get_from(id))

@sync begin
    # put! and take! blocking, so we use async
    @async put!(A)
    @async @fetchfrom 2 take!(ac_get_from(id))
end
```

While the local array duplication of `A` at process two began unitialised, performing matching `put!` and `take!` operations causes A's contents to be updated at process 2.

The following parallelism patterns are to be supported soon, following optimisation of the `put!` and `take!` abstractions. They provide additional conveniences to the `ArrayChannels.jl` library.

`put!` and `take!` cover the functionality of either a `Broadcast` or `Send / Receive` currently, as the sender may specify the recipient processes on call.

* **Scatter** / **Gather**
* **Reduce**

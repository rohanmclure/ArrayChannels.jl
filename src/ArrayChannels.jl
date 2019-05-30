module ArrayChannels

# Precompile imports
import Distributed
import Serialization
import Sockets
import Core

# Dependency unqualified imports
import Base: ReentrantLock
import Distributed: RRID, WorkerPool, @spawnat, @fetchfrom, @everywhere, nprocs, procs, myid, remotecall_wait, remotecall_fetch, copy!
import Serialization: AbstractSerializer, serialize, deserialize, serialize_cycle_header, serialize_type, writetag, deserialize_fillarray!, AbstractSerializer, OBJECT_TAG
import Base: AbstractChannel, put!, take!, size, show, getindex, setindex!, fill!, length, broadcast, broadcast!, iterate

export
    ArrayChannel,
    ac_get_from,
    put!,
    take!,
    reduce!,
    getindex,
    setindex!,
    fill!

include("inplacearray.jl")
include("arraychannels.jl")
include("precompile.jl")

end

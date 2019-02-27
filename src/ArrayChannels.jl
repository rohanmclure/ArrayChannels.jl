module ArrayChannels

import Base.Threads: Event, @threads
import Distributed: RRID, WorkerPool, @fetchfrom, @everywhere, procs, myid, remotecall_wait, remotecall_fetch
import Serialization: AbstractSerializer, serialize, deserialize, serialize_cycle_header, serialize_type, writetag, deserialize_fillarray!, AbstractSerializer, OBJECT_TAG
import Base: AbstractChannel, put!, take!, size, show, getindex, setindex!

export
    ArrayChannel,
    ac_get_from,
    put!,
    take!,
    getindex,
    setindex!

include("arraychannels.jl")
include("inplacearray.jl")

end

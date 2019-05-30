precompile(Tuple{ArrayChannels.get_arraychannel, Distributed.RRID})
precompile(Tuple{ArrayChannels.ac_get_from, Distributed.RRID})
precompile(Tuple{ArrayChannels.put!, ArrayChannel, Int64, Union{RRID,Nothing}})
precompile(Tuple{ArrayChannels.take!, ArrayChannel, Int64})

precompile(Tuple{ArrayChannels.deserialize, Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Union}})
precompile(Tuple{ArrayChannels.deserialize, Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Module}})
precompile(Tuple{ArrayChannels.deserialize, Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Core.SimpleVector}})

precompile(Tuple{ArrayChannels.deserialize_helper, Distributed.RRID, Int64, Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Array}})

precompile(Tuple{Serialization.deserialize, Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Union}})
precompile(Tuple{Serialization.deserialize, Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Module}})
precompile(Tuple{Serialization.deserialize, Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Core.SimpleVector}})

precompile(Tuple{typeof(Serialization.deserialize), Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Union}})
precompile(Tuple{typeof(Serialization.deserialize), Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Module}})
precompile(Tuple{typeof(Serialization.deserialize), Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Core.SimpleVector}})

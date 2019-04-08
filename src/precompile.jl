precompile(Tuple{ArrayChannels.get_arraychannel, Distributed.RRID})
precompile(Tuple{ArrayChannels.ac_get_from, Distributed.RRID})
precompile(Tuple{ArrayChannels.put!, ArrayChannel})
precompile(Tuple{ArrayChannels.take!, ArrayChannel})

precompile(Tuple{ArrayChannels.deserialize, Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Union}})
precompile(Tuple{ArrayChannels.deserialize, Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Module}})
precompile(Tuple{ArrayChannels.deserialize, Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Core.SimpleVector}})

precompile(Tuple{ArrayChannels.deserialize_helper, Distributed.RRID, Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Array}})

precompile(Tuple{Serialization.deserialize, Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Union}})
precompile(Tuple{Serialization.deserialize, Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Module}})
precompile(Tuple{Serialization.deserialize, Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Core.SimpleVector}})

precompile(Tuple{typeof(Serialization.deserialize), Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Union}})
precompile(Tuple{typeof(Serialization.deserialize), Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Module}})
precompile(Tuple{typeof(Serialization.deserialize), Distributed.ClusterSerializer{Sockets.TCPSocket}, Type{Core.SimpleVector}})

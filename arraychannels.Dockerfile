FROM julia-debug-build

WORKDIR /
RUN ln -s /julia/julia /usr/bin

ADD . arraychannels
WORKDIR arraychannels

# CMD julia --load preload.jl

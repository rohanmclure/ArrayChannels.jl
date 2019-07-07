FROM julia:1.1.0

# Install Jupyter
RUN apt update
RUN apt install -y bzip2
RUN apt install -y python3-pip
RUN python3 -m pip install jupyter
RUN useradd -m jupyter 

# Install ArrayChannels
ADD . /home/jupyter/arraychannels
RUN chown jupyter /home/jupyter/arraychannels /home/jupyter/arraychannels/*
USER jupyter
WORKDIR /home/jupyter/arraychannels
RUN julia -e "using Pkg; Pkg.activate(\".\"); Pkg.resolve()"
RUN julia -e "using Pkg; Pkg.add(\"Distributed\"); Pkg.add(\"Serialization\"); Pkg.add(\"Sockets\"); Pkg.develop(PackageSpec(path=\".\"))"

EXPOSE 8888

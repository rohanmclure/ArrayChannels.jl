FROM julia:1.1.0

# Install Jupyter
RUN apt-get update
RUN apt-get install -y bzip2 python3-pip
RUN python3 -m pip install jupyter
RUN useradd -m jupyter

# Install ArrayChannels
ADD . /home/jupyter/arraychannels
RUN chown jupyter /home/jupyter/arraychannels /home/jupyter/arraychannels/*
USER jupyter
WORKDIR /home/jupyter/arraychannels
RUN julia -e "using Pkg; Pkg.add(\"IJulia\"); using IJulia"
RUN julia -e "using Pkg; Pkg.activate(\".\"); Pkg.resolve()"
RUN julia -e "using Pkg; Pkg.add(\"Distributed\"); Pkg.add(\"Serialization\"); Pkg.add(\"Sockets\"); Pkg.develop(PackageSpec(path=\".\"))"

EXPOSE 8888

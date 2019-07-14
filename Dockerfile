FROM julia:1.1.0

# Install Jupyter
RUN apt-get update
RUN apt-get install -y bzip2 python3-pip
RUN python3 -m pip install jupyter
RUN useradd -m jupyter

# Install ArrayChannels
USER jupyter
COPY --chown=jupyter . /home/jupyter/ArrayChannels
WORKDIR /home/jupyter/
RUN julia -e "using Pkg; Pkg.add(\"IJulia\"); using IJulia"
RUN julia -e "using Pkg; Pkg.activate(\"./ArrayChannels\"); Pkg.resolve()"
RUN julia -e "using Pkg; Pkg.add(\"Distributed\"); Pkg.add(\"Serialization\"); Pkg.add(\"Sockets\"); Pkg.develop(PackageSpec(path=\"./ArrayChannels\")); using ArrayChannels"

EXPOSE 8888

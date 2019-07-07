FROM julia:1.1.0

ADD . arraychannels
WORKDIR arraychannels
RUN julia -e "using Pkg; Pkg.activate(\".\"); Pkg.resolve()"
RUN julia -e "using Pkg; Pkg.add(\"Distributed\"); Pkg.add(\"Serialization\"); Pkg.add(\"Sockets\"); Pkg.develop(PackageSpec(path=\".\"))"

# Install Jupyter
RUN apt update
RUN apt install -y bzip2
RUN apt install -y python3-pip
RUN python3 -m pip install jupyter

# Create Docker environment
EXPOSE 8888
CMD python3 -m jupyter notebook --ip=0.0.0.0 --port=8888 --allow-root

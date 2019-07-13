CC = gcc
MPICC = mpicc

clean:

ping_pong:
	$(MPICC) example/ping_pong.c -o example/ping_pong

reduce: prk
	cd example && $(MPICC) reduce.c -o reduce

transpose:
	cd example && $(MPICC) transpose.c -o transpose

stencil:
	cd example && $(MPICC) stencil.c -o stencil

prk:
	# Do something or rather else

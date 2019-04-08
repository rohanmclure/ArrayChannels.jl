CC = gcc 
MPICC = mpicc 

clean:
	
ping_pong:
	$(MPICC) example/ping_pong.c -o example/ping_pong

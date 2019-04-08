#include <mpi.h>
#include <stdio.h>
#include <time.h>
#include <sys/time.h>
#include <stdlib.h>

/*
  Call me with mpirun -np 2 ping_pong <iterations> <payload>
*/
double get_wall_time(){
    struct timeval time;
    if (gettimeofday(&time,NULL)){
        //  Handle error
        return 0;
    }
    return (double)time.tv_sec + (double)time.tv_usec * .000001;
}

int main(int argc, char** argv) {
  const int root = 0;
  int payload;
  int iterations;

  MPI_Init(&argc,&argv);
  int rank;
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);
  int num_ranks;
  MPI_Comm_size(MPI_COMM_WORLD, &num_ranks);

  if (rank == root) {
    // Let's in fact require two ranks for this exercise
    if (num_ranks != 2) {
      fprintf(stderr, "%s\n", "We expect only two ranks.");
      MPI_Abort(MPI_COMM_WORLD, 1);
    }

    if (argc != 3) {
      printf("Usage: %s <# iterations> <vector_length>\n", *argv);
      MPI_Abort(MPI_COMM_WORLD, 1);
    }

    iterations = atoi(*++argv);
    if (iterations <= 0) {
      fprintf(stderr, "%s\n", "Specify at least one iteration.");
      MPI_Abort(MPI_COMM_WORLD, 1);
    }

    payload = atoi(*++argv);
    if (payload <= 0) {
      fprintf(stderr, "%s\n", "Arrays should be non-empty.");
      MPI_Abort(MPI_COMM_WORLD, 1);
    }
  }

  MPI_Bcast(&iterations, 1, MPI_INT, root, MPI_COMM_WORLD);
  MPI_Bcast(&payload, 1, MPI_INT, root, MPI_COMM_WORLD);
  double* vector = malloc(payload * sizeof(double));

  for (int i = 0; i < payload; i++) {
    vector[i] = (double) i;
  }

  MPI_Barrier(MPI_COMM_WORLD);

  /*
    MPI_Send(
      void* data,
      int count,
      MPI_Datatype datatype,
      int destination,
      int tag,
      MPI_Comm communicator)
    MPI_Recv(
      void* data,
      int count,
      MPI_Datatype datatype,
      int source,
      int tag,
      MPI_Comm communicator,
      MPI_Status* status)
  */
  double t0, t1;
  if (rank == root) {
    t0 = get_wall_time();
  }

  int partner_rank = (rank + 1) % 2;
  int k = 0;
  for (int k = 0; k < iterations; k++) {
    if (rank == k % 2) {
      vector[k % payload] += (double) k; // Slight modification
      MPI_Send(vector, payload, MPI_DOUBLE, partner_rank, /*Tag*/ 0, MPI_COMM_WORLD);
    } else {
      MPI_Recv(vector, payload, MPI_DOUBLE, partner_rank, 0, MPI_COMM_WORLD,
               MPI_STATUS_IGNORE);
    }
  }

  if (rank == root) {
    t1 = get_wall_time();
    printf("%.9f MB/s\n", ((double) (iterations * payload) * 8.0) * (1e-6) / (t1-t0));
  }

  MPI_Finalize();
}

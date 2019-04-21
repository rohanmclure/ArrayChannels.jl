#include <mpi.h>
#include <stdio.h>
#include <time.h>
#include <sys/time.h>
#include <stdlib.h>

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
  int payload, iterations;

  MPI_Init(&argc, &argv);
  int rank;
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);
  int num_ranks;
  MPI_Comm_size(MPI_COMM_WORLD, &num_ranks);

  if (rank == root) {
    if (num_ranks < 2) {
      fprintf(stderr, "%s\n", "We expect at least two ranks.");
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
  double* vector = malloc(payload * 2 * sizeof(double));
  double* ones = vector + payload;

  for (int i = 0; i < payload; i++) {
    vector[i] = 1.0;
    ones[i] = 1.0;
  }

  double t0, t1;
  for (int k = 0; k <= iterations; k++) {
    if (k == 1) {
      MPI_Barrier(MPI_COMM_WORLD);
      t0 = get_wall_time();
    }

    for (int i = 0; i < payload; i++) {
      vector[i] += ones[i];
    }

    if (rank == root) {
      MPI_Reduce(MPI_IN_PLACE, vector, payload, MPI_DOUBLE, MPI_SUM,
                 root, MPI_COMM_WORLD);
    } else {
      MPI_Reduce(vector, NULL, payload, MPI_DOUBLE, MPI_SUM,
                 root, MPI_COMM_WORLD);
    }
  }
  t1 = get_wall_time();

  if (rank == root) {
    printf("%.9f MFlops/s\n", (1e-6 * (2.0*num_ranks-1.0) * payload * iterations) / (t1-t0));
  }
}

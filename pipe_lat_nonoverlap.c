/*
    Measure latency of IPC using unix domain sockets


    Copyright (c) 2016 Erik Rigtorp <erik@rigtorp.se>

    Permission is hereby granted, free of charge, to any person
    obtaining a copy of this software and associated documentation
    files (the "Software"), to deal in the Software without
    restriction, including without limitation the rights to use,
    copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the
    Software is furnished to do so, subject to the following
    conditions:

    The above copyright notice and this permission notice shall be
    included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
    OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
    NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
    HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
    WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
    OTHER DEALINGS IN THE SOFTWARE.
*/

#define _GNU_SOURCE
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
#include "KUtils.h"

#if defined(_POSIX_TIMERS) && (_POSIX_TIMERS > 0) &&                           \
    defined(_POSIX_MONOTONIC_CLOCK)
#define HAS_CLOCK_GETTIME_MONOTONIC
#endif

#define errExit(msg)	do { perror(msg); exit(EXIT_FAILURE); \
							  } while (0)

typedef int bool;
#define false 0
#define true  1

#define SCALE 2

int main(int argc, char *argv[]) {
  int ofds[2];
  int ifds[2];

  int size;
  char *buf, *buf2Half;
  int64_t count, i, delta;
#ifdef HAS_CLOCK_GETTIME_MONOTONIC
  struct timespec start, stop;
#else
  struct timeval start, stop;
#endif
  cpu_set_t set;
  int parentCPU, childCPU;
  bool isEnableAngelSignals;

  if (argc != 6) {
    printf("usage: pipe_lat_nonoverlap <message-size> <roundtrip-count> <parent cpu> <child cpu> <Enable(1)/Disable(0) angel signals>\n");
    return 1;
  }

  size = atoi(argv[1]);
  count = atol(argv[2]);
  parentCPU = atoi(argv[3]);
  childCPU = atoi(argv[4]);
  isEnableAngelSignals = atoi(argv[5]);
  CPU_ZERO(&set);

  buf = malloc(size * SCALE);
  if (buf == NULL) {
    perror("malloc");
    return 1;
  }
  buf2Half = buf + size;

  printf("message size: %i octets\n", size);
  printf("roundtrip count: %li\n", count);

  if (pipe(ofds) == -1) {
    perror("pipe");
    return 1;
  }

  if (pipe(ifds) == -1) {
    perror("pipe");
    return 1;
  }

  if (!fork()) { /* child */
    CPU_SET(childCPU, &set);

    /*char *bufC;
    bufC = malloc(size);
      if (bufC == NULL) {
        perror("malloc");
        return 1;
    }
    printf("Buffer pointer client=%p\n", bufC);*/
    memset((void *)buf, 0x00, size*SCALE);

    if (sched_setaffinity(getpid(), sizeof(set), &set) == -1){
     errExit("sched_setaffinity of child failed");
    }

    for (i = 0; i < count; i++) {

      if (read(ifds[0], buf, size) != size) {
        perror("read");
        return 1;
      }

      if (write(ofds[1], buf, size) != size) {
        perror("write");
        return 1;
      }
    }
  } else { /* parent */
    CPU_SET(parentCPU, &set);

    /*char *bufP, *bufP2Half;
    bufP = malloc(size*SCALE);
    if (bufP == NULL) {
        perror("malloc");
        return 1;
    }
    bufP2Half = bufP + size;
    //printf("Buffer pointer server=%p and 2Half=%p\n", bufP, bufP2Half);*/
    memset((void *)buf, 0x00, size*SCALE);

    if (sched_setaffinity(getpid(), sizeof(set), &set) == -1){
     errExit("sched_setaffinity of parent failed");
    }

#ifdef ANGEL
    if( isEnableAngelSignals )
    {
      workload_ckpt_begin();
    }
#endif

#ifdef HAS_CLOCK_GETTIME_MONOTONIC
    if (clock_gettime(CLOCK_MONOTONIC, &start) == -1) {
      perror("clock_gettime");
      return 1;
    }
#else
    if (gettimeofday(&start, NULL) == -1) {
      perror("gettimeofday");
      return 1;
    }
#endif

    for (i = 0; i < count; i++) {

      if (write(ifds[1], buf2Half, size) != size) {
        perror("write");
        return 1;
      }

      if (read(ofds[0], buf2Half, size) != size) {
        perror("read");
        return 1;
      }
    }

#ifdef HAS_CLOCK_GETTIME_MONOTONIC
    if (clock_gettime(CLOCK_MONOTONIC, &stop) == -1) {
      perror("clock_gettime");
      return 1;
    }

    delta = ((stop.tv_sec - start.tv_sec) * 1000000000 +
             (stop.tv_nsec - start.tv_nsec));

#else
    if (gettimeofday(&stop, NULL) == -1) {
      perror("gettimeofday");
      return 1;
    }

    delta =
        (stop.tv_sec - start.tv_sec) * 1000000000 + (stop.tv_usec - start.tv_usec) * 1000;

#endif

    printf("average latency: %li ns\n", delta / (count * 2));
#ifdef ANGEL
    if( isEnableAngelSignals )
    {
      workload_ckpt_end();
    }
#endif

  }

  return 0;
}

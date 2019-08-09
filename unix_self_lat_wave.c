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

int main(int argc, char *argv[]) {
  int sv[2]; /* the pair of socket descriptors */
  int size;
  char *buf;
  int64_t count, i, delta;
#ifdef HAS_CLOCK_GETTIME_MONOTONIC
  struct timespec start, stop;
#else
  struct timeval start, stop;
#endif
  cpu_set_t set;
  int parentCPU;
  bool isEnableAngelSignals;

  if (argc != 5) {
    printf("usage: unix_self_lat <message-size> <roundtrip-count> <parent cpu> <Enable(1)/Disable(0) angel signals>\n");
    return 1;
  }

  size = atoi(argv[1]);
  count = atol(argv[2]);
  parentCPU = atoi(argv[3]);
  isEnableAngelSignals = atoi(argv[4]);
  CPU_ZERO(&set);

  buf = malloc(size);
  if (buf == NULL) {
    perror("malloc");
    return 1;
  }

  printf("message size: %i octets\n", size);
  printf("roundtrip count: %li\n", count);

  if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) == -1) {
    perror("socketpair");
    return 1;
  }

  /* parent */
  CPU_SET(parentCPU, &set);

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
#ifdef RTLWAVE
    trigger_waves();
#endif

    if (write(sv[0], buf, size) != size) {
      perror("write socket 0");
      return 1;
    }

    if (read(sv[1], buf, size) != size) {
      perror("read socket 1");
      return 1;
    }

    if (write(sv[1], buf, size) != size) {
      perror("write socket 1");
      return 1;
    }

    if (read(sv[0], buf, size) != size) {
      perror("read socket 0");
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

  return 0;
}

/*
    Measure latency of IPC using tcp sockets


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
#include <string.h>
#include <sys/socket.h>
#include <netdb.h>
#include "KUtils.h"
#include <time.h>
#include <unistd.h>

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
  int size;
  char *buf;
  int64_t count, i, delta;
#ifdef HAS_CLOCK_GETTIME_MONOTONIC
  struct timespec start, stop;
#elif defined(HAS_GETTIMEOFDAY)
  struct timeval start, stop;
#elif defined(PERF_INSTRUMENT)
  double beginC, endC;
#endif
  cpu_set_t set;
  int parentCPU, childCPU;
  bool isEnableAngelSignals;

  ssize_t len;
  size_t sofar;

  int yes = 1;
  int ret;
  struct sockaddr_storage their_addr;
  socklen_t addr_size;
  struct addrinfo hints;
  struct addrinfo *res;
  int sockfd, new_fd;

  if (argc != 6) {
    printf("usage: tcp_lat <message-size> <roundtrip-count> <parent cpu> <child cpu> <Enable(1)/Disable(0) angel signals>\n");
    return 1;
  }

  size = atoi(argv[1]);
  count = atol(argv[2]);
  parentCPU = atoi(argv[3]);
  childCPU = atoi(argv[4]);
  isEnableAngelSignals = atoi(argv[5]);
  CPU_ZERO(&set);

#ifdef PERF_INSTRUMENT
   perf_event_init( (enable_perf_events) ENABLE_HW_CYCLES_PER );
   perf_event_enable ( (enable_perf_events) ENABLE_HW_CYCLES_PER );
#endif //PERF_INSTRUMENT_PER

  buf = malloc(size);
  if (buf == NULL) {
    perror("malloc");
    return 1;
  }

  memset(&hints, 0, sizeof hints);
  hints.ai_family = AF_UNSPEC; // use IPv4 or IPv6, whichever
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_flags = AI_PASSIVE; // fill in my IP for me
  if ((ret = getaddrinfo("127.0.0.1", "3491", &hints, &res)) != 0) {
    fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(ret));
    return 1;
  }

  printf("message size: %i octets\n", size);
  printf("roundtrip count: %li\n", count);

  if (!fork()) { /* child */
    CPU_SET(childCPU, &set);

    if (sched_setaffinity(getpid(), sizeof(set), &set) == -1){
     errExit("sched_setaffinity of child failed");
    }

    if ((sockfd = socket(res->ai_family, res->ai_socktype, res->ai_protocol)) ==
        -1) {
      perror("socket");
      return 1;
    }

    if (setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(int)) == -1) {
      perror("setsockopt");
      return 1;
    }

    if (bind(sockfd, res->ai_addr, res->ai_addrlen) == -1) {
      perror("bind");
      return 1;
    }

    if (listen(sockfd, 1) == -1) {
      perror("listen");
      return 1;
    }

    addr_size = sizeof their_addr;

    if ((new_fd = accept(sockfd, (struct sockaddr *)&their_addr, &addr_size)) ==
        -1) {
      perror("accept");
      return 1;
    }

    for (i = 0; i < count; i++) {

      for (sofar = 0; sofar < size;) {
        len = read(new_fd, buf, size - sofar);
        if (len == -1) {
          perror("read");
          return 1;
        }
        sofar += len;
      }

      if (write(new_fd, buf, size) != size) {
        perror("write");
        return 1;
      }
    }
  } else { /* parent */

    sleep(1);

    CPU_SET(parentCPU, &set);

    if (sched_setaffinity(getpid(), sizeof(set), &set) == -1){
     errExit("sched_setaffinity of parent failed");
    }

    if ((sockfd = socket(res->ai_family, res->ai_socktype, res->ai_protocol)) ==
        -1) {
      perror("socket");
      return 1;
    }

    if (connect(sockfd, res->ai_addr, res->ai_addrlen) == -1) {
      perror("connect");
      return 1;
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
#elif defined(HAS_GETTIMEOFDAY)
    if (gettimeofday(&start, NULL) == -1) {
      perror("gettimeofday");
      return 1;
    }
#elif defined(PERF_INSTRUMENT)
    beginC = perf_per_cycle_event_read();
#endif

    for (i = 0; i < count; i++) {
#ifdef RTLWAVE
    trigger_waves();
#endif

      if (write(sockfd, buf, size) != size) {
        perror("write");
        return 1;
      }

      for (sofar = 0; sofar < size;) {
        len = read(sockfd, buf, size - sofar);
        if (len == -1) {
          perror("read");
          return 1;
        }
        sofar += len;
      }
    }

#ifdef HAS_CLOCK_GETTIME_MONOTONIC
    if (clock_gettime(CLOCK_MONOTONIC, &stop) == -1) {
      perror("clock_gettime");
      return 1;
    }

    delta = ((stop.tv_sec - start.tv_sec) * 1000000000 +
             (stop.tv_nsec - start.tv_nsec));

    printf("Clock average latency: %li ns\n", delta / (count * 2));
#elif defined(HAS_GETTIMEOFDAY)
    if (gettimeofday(&stop, NULL) == -1) {
      perror("gettimeofday");
      return 1;
    }

    delta =
        (stop.tv_sec - start.tv_sec) * 1000000000 + (stop.tv_usec - start.tv_usec) * 1000;
    printf("GTOD average latency %li ns\n", delta/ (count*2));
#elif defined(PERF_INSTRUMENT)
   endC = perf_per_cycle_event_read();
   delta = endC - beginC;

   printf("Perf average cycle: %li\n", delta / (count * 2));
#else
   printf("Not supported\n");
#endif

#ifdef ANGEL
    if( isEnableAngelSignals )
    {
      workload_ckpt_end();
    }
#endif
  }

  return 0;
}

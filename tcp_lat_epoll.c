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
#include <sys/epoll.h>
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
#include <errno.h>

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
  int64_t count, delta;
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

  int yes = 1;
  int ret;
  struct sockaddr_storage their_addr;
  socklen_t addr_size;
  struct addrinfo hints;
  struct addrinfo *res;
  int sockfd, new_fd;

  if (argc != 6) {
    printf("usage: tcp_lat_epoll <message-size> <roundtrip-count> <parent cpu> <child cpu> <Enable(1)/Disable(0) angel signals>\n");
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
  hints.ai_family = AF_INET; // use IPv4 or IPv6, whichever
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

    if ((sockfd = socket(res->ai_family, res->ai_socktype, IPPROTO_IP)) ==
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

    if ((new_fd = accept4(sockfd, (struct sockaddr *)&their_addr, &addr_size, SOCK_NONBLOCK )) ==
        -1) {
      perror("accept");
      return 1;
    }

    int s,efd = epoll_create1(0);
    struct epoll_event event;
    struct epoll_event *events;
    event.data.fd = new_fd;
    event.events = EPOLLIN|EPOLLRDHUP|EPOLLET;
    s = epoll_ctl (efd, EPOLL_CTL_ADD, new_fd, &event);
    if(s == -1) {
       perror ("epoll_ctl");
       exit(1);
    }
    events = calloc (64, sizeof event);

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
    int r_count =0;
    int j, done=0;
    while(1) {
        int n = epoll_wait (efd, events, 64, 65000);
        for (j = 0; j < n; j++) {
              if ((events[j].events & EPOLLERR) ||
                 (events[j].events & EPOLLHUP) ||
                 (!(events[j].events & EPOLLIN)))
              {
                        perror ("epoll error\n");
                        close (events[j].data.fd);
                        continue;
              }
              if(events[j].events & EPOLLIN) {
                   while(1) {
                        len = recv(events[j].data.fd, buf, size, 0);
                        if (len == -1) {
                             if(errno != EAGAIN) {
                                      perror("recv err\n");
                                      done = 1;
                             }
                             break;
                        }
                        else if (len == 0) {
                             perror("sock closed\n");
			     done = 1;
                             break;
                        }
                        r_count++;
                        if(r_count == count)
			{
			     done = 1;
                             break;
			}
                    }
                }
           }
           if(done)
                   break;

        }
        free (events);
        close(new_fd);

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

    printf("Clock recv latency: %li ns\n", delta / (count ));


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

    int s,efd = epoll_create1(0);
    struct epoll_event event;
    struct epoll_event *events;
    event.data.fd = sockfd;
    event.events = EPOLLOUT;
    s = epoll_ctl (efd, EPOLL_CTL_ADD, sockfd, &event);
    if(s == -1) {
       perror ("epoll_ctl");
       exit(1);
    }
    events = calloc (64, sizeof event);

    struct iovec iobuf;
    iobuf.iov_base = buf;
    iobuf.iov_len= size;
    int w_count = 0;

    while(1) {
           int j;
           int n = epoll_wait (efd, events, 64, 65000);
           for (j = 0; j < n; j++) {
                if(events[j].events & EPOLLOUT) {
                      if (writev(sockfd, &iobuf, 1) != size) {
                          perror("write err\n");
			  break;
                      }

                      w_count++;
                }
           }
           if(w_count == count)
                break;
    }



#ifdef HAS_CLOCK_GETTIME_MONOTONIC
    if (clock_gettime(CLOCK_MONOTONIC, &stop) == -1) {
      perror("clock_gettime");
      return 1;
    }

    delta = ((stop.tv_sec - start.tv_sec) * 1000000000 +
             (stop.tv_nsec - start.tv_nsec));

    printf("Clock average latency: %li ns\n", delta / (count));
#elif defined(HAS_GETTIMEOFDAY)
    if (gettimeofday(&stop, NULL) == -1) {
      perror("gettimeofday");
      return 1;
    }

    delta =
        (stop.tv_sec - start.tv_sec) * 1000000000 + (stop.tv_usec - start.tv_usec) * 1000;
    printf("GTOD average latency %li ns\n", delta/ (count));
#elif defined(PERF_INSTRUMENT)
   endC = perf_per_cycle_event_read();
   delta = endC - beginC;

   printf("Perf send latency: %li\n", delta / (count));
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

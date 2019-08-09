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
#include <netinet/tcp.h>
#if defined(_POSIX_TIMERS) && (_POSIX_TIMERS > 0) &&                           \
    defined(_POSIX_MONOTONIC_CLOCK)
#define HAS_CLOCK_GETTIME_MONOTONIC
#endif

#define errExit(msg)	do { perror(msg); exit(EXIT_FAILURE); \
							  } while (0)

typedef int bool;
#define false 0
#define true  1
#define EPOLL_ARRAY_SIZE   64
int main(int argc, char *argv[]) {
  int server_send_size, client_send_size;
  char *client_rbuf, *client_wbuf, *server_rbuf, *server_wbuf;
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
  int tcp_nopush = 0;
  int tcp_nodelay = 0;

#ifdef ANGEL
  if (argc != 9) {
    printf("usage: tcp_lat_epoll_with_ack <server-send-size> <client-send-size> <roundtrip-count> <tcp_nodelay:0|1> <tcp_nopush:0|1> <parent cpu> <child cpu> <Enable(1)/Disable(0) angel signals>\n");
#else
  if (argc != 8) {
    printf("usage: tcp_lat_epoll_with_ack <server-send-size> <client-send-size> <roundtrip-count> <tcp_nodelay:0|1> <tcp_nopush:0|1> <parent cpu> <child cpu>\n");
#endif
    return 1;
  }
  server_send_size = atoi(argv[1]);
  client_send_size = atoi(argv[2]);
  count = atol(argv[3]);
  tcp_nodelay = atoi(argv[4]);
  tcp_nopush = atoi(argv[5]);
  parentCPU = atoi(argv[6]);
  childCPU = atoi(argv[7]);
#ifdef ANGEL
  isEnableAngelSignals = atoi(argv[8]);
#endif
  CPU_ZERO(&set);

#ifdef PERF_INSTRUMENT
   perf_event_init( (enable_perf_events) ENABLE_HW_CYCLES_PER );
   perf_event_enable ( (enable_perf_events) ENABLE_HW_CYCLES_PER );
#endif //PERF_INSTRUMENT_PER

  client_rbuf = malloc(server_send_size);
  server_wbuf = malloc(server_send_size);
  client_wbuf = malloc(client_send_size);
  server_rbuf = malloc(client_send_size);
  if ( (client_rbuf == NULL) || (client_wbuf == NULL) || (server_rbuf == NULL) || (server_wbuf == NULL) ){
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

  printf("server send message size: %d, client send message size: %d\n", server_send_size, client_send_size);
  printf("roundtrip count: %li\n", count);

  if (!fork()) { /* server */
    CPU_SET(childCPU, &set);

    if (sched_setaffinity(getpid(), sizeof(set), &set) == -1) {
     errExit("sched_setaffinity of child failed");
    }

    if ((sockfd = socket(res->ai_family, res->ai_socktype, IPPROTO_IP)) == -1) {
      perror("socket");
      return 1;
    }

    if (setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(int)) == -1) {
      perror("setsockopt");
      return 1;
    }

    if(tcp_nodelay) {
	setsockopt(sockfd, SOL_TCP, TCP_NODELAY, &tcp_nodelay, 4);
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
    events = calloc (EPOLL_ARRAY_SIZE, sizeof event);
    s = epoll_ctl (efd, EPOLL_CTL_ADD, new_fd, &event);
    if(s == -1) {
       perror ("epoll_ctl EPOLL_CTL_ADD");
       exit(1);
    }

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
    int sw_count = 0, sr_count = 0, cork = 0;
    struct iovec iobuf;
    iobuf.iov_base = server_wbuf;
    iobuf.iov_len= server_send_size;
    do{
        int n = epoll_wait (efd, events, EPOLL_ARRAY_SIZE, -1);

        for (int j = 0; j < n; j++) {
          if (events[j].events & EPOLLERR)
          {
            printf ("Server: epoll event error: 0x%x\n", events[j].events);
            continue;
          }

          if (events[j].events & EPOLLRDHUP)
          {
            printf ("Server: Stream socket peer closed connection error: 0x%x\n", events[j].events);
            exit(1);
          }

          if(events[j].events & EPOLLIN) {
            len = recv(events[j].data.fd, server_rbuf, client_send_size, 0);
            if (len == -1) {
                 if(errno != EAGAIN) {
                     perror("recv err\n");
                 }
                 break;
            }
            else if (len == 0) {
                 perror("Server: sock closed\n");
                 exit(1);
                 break;
            }
            sr_count++;
            cork = 1;

            if(tcp_nopush) {
              setsockopt(sockfd, SOL_TCP, TCP_CORK, &cork, 4);
            }

            if (writev(events[j].data.fd, &iobuf, 1) != server_send_size) {
              perror("write err\n");
              break;
            }

            cork = 0;
            if(tcp_nopush) {
              setsockopt(sockfd, SOL_TCP, TCP_CORK, &cork, 4);
            }
            sw_count++;
          }
        } //End of for loop

        if ( (sr_count == count) || (sw_count == count) ) {
          break;
        }

     } while(1);
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

    printf("Server: Clock recv latency: %li ns\n", delta / (count ));


  } else { /* client */

    sleep(1);

    CPU_SET(parentCPU, &set);

    if (sched_setaffinity(getpid(), sizeof(set), &set) == -1){
     errExit("sched_setaffinity of parent failed");
    }

    if ((sockfd = socket(res->ai_family, res->ai_socktype, res->ai_protocol)) == -1) {
      perror("socket");
      return 1;
    }

    if (connect(sockfd, res->ai_addr, res->ai_addrlen) == -1) {
      perror("connect");
      return 1;
    }
    if(tcp_nodelay)
	setsockopt(sockfd, SOL_TCP, TCP_NODELAY, &tcp_nodelay, 4);
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
    event.events = EPOLLOUT|EPOLLRDHUP|EPOLLET;
    events = calloc (EPOLL_ARRAY_SIZE, sizeof event);
    s = epoll_ctl (efd, EPOLL_CTL_ADD, sockfd, &event);
    if(s == -1) {
       perror ("epoll_ctl EPOLL_CTL_ADD");
       exit(1);
    }
    struct iovec iobuf;
    iobuf.iov_base = client_wbuf;
    iobuf.iov_len= client_send_size;
    int cw_count = 0, cr_count = 0, wr_rd = 0;

    do {
           int n = epoll_wait (efd, events, EPOLL_ARRAY_SIZE, -1);

           for (int j = 0; j < n; j++) {
              if (events[j].events & EPOLLERR)
              {
                printf ("Client: epoll event error: 0x%x\n", events[j].events);
                continue;
              }

              if (events[j].events & EPOLLRDHUP)
              {
                printf ("Client: Stream socket peer closed connection error: 0x%x\n", events[j].events);
	       		    exit(1);
              }

              if(events[j].events & EPOLLOUT) {
                if (writev(sockfd, &iobuf, 1) != client_send_size) {
                    perror("write err\n");
                    break;
                }
                wr_rd = 1;
                cw_count++;
              }

              if(events[j].events & EPOLLIN) {
                int rlen = recv(events[j].data.fd, client_rbuf, server_send_size, 0);
                if (rlen == -1) {
                   if(errno != EAGAIN) {
                     perror("recv err\n");
                   }
                   break;
                }
                else if (rlen == 0) {
                   perror("Client: received ZERO\n");
                   exit(1);
                   break;
                }
                wr_rd = 0;
                cr_count++;
              }
           }

           if( (cw_count == count) || (cr_count == count) ) {
                break;
           }
#if 1
	   if (wr_rd) {
    	 event.events = EPOLLIN;
     }
	   else {
    	 event.events = EPOLLOUT;
     }

     s = epoll_ctl (efd, EPOLL_CTL_MOD, sockfd, &event);
	   if(s == -1) {
	       perror ("Client: epoll_ctl EPOLL_CTL_MOD");
	       exit(1);
	   }
#endif
    } while (1);
    free (events);
    close(sockfd);

#ifdef HAS_CLOCK_GETTIME_MONOTONIC
    if (clock_gettime(CLOCK_MONOTONIC, &stop) == -1) {
      perror("clock_gettime");
      return 1;
    }

    delta = ((stop.tv_sec - start.tv_sec) * 1000000000 +
             (stop.tv_nsec - start.tv_nsec));

    printf("Client : Clock average latency: %li ns\n", delta / (count));
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

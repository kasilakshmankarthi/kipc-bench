ifeq ($(ARCH),aarch64)
    base=/prj/dcg/modeling/encnaa/workloads/share/toolchains/gcc-7.1.1-linaro17.08
    CC=${base}/aarch64-linux-gnu/bin/aarch64-linux-gnu-gcc

    local_angel=./disk/angel-utils
    local_angel_include=$(local_angel)/libangel/include
    local_angel_lib=$(local_angel)/build

    CFLAGS  = -static -g -Wall -O3 -D RTLWAVE -DANGEL -I$(local_angel_include)
    LDFLAGS = -static -L$(local_angel_lib) -langel
else
    base=/usr/bin
    CC=${base}/gcc

    CFLAGS = -static -g -Wall -O3
    LDFLAGS =
endif

ifeq ($(ARCH),aarch64)
all: pipe_lat pipe_lat_nonoverlap pipe_self_lat pipe_thr \
	unix_lat unix_lat_nonoverlap unix_self_lat unix_thr \
	tcp_lat tcp_lat_nonoverlap   tcp_self_lat tcp_thr \
	tcp_local_lat tcp_remote_lat \
	udp_lat \
	tcp_self_lat_wave unix_self_lat_wave \
	tcp_lat_wave \
	tcp_lat_epoll tcp_lat_epoll_with_ack
else
all: pipe_lat pipe_lat_nonoverlap pipe_self_lat pipe_thr \
	unix_lat unix_lat_nonoverlap unix_self_lat unix_thr \
	tcp_lat tcp_lat_nonoverlap tcp_self_lat tcp_thr \
	tcp_local_lat tcp_remote_lat \
	udp_lat \
	tcp_lat_epoll tcp_lat_epoll_with_ack
endif

.c:
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

run:
	./binaries/pipe_lat.$(ARCH).elf 100 10000 1 1 0
	./binaries/unix_lat.$(ARCH).elf 100 10000 1 1 0
	./binaries/tcp_lat.$(ARCH).elf 100 10000 1 1 0
	./binaries/pipe_self_lat.$(ARCH).elf 100 10000 1 0
	./binaries/unix_self_lat.$(ARCH).elf 100 10000 1 0
	./binaries/tcp_self_lat.$(ARCH).elf 100 10000 1 0
	./binaries/tcp_lat_epoll.$(ARCH).elf 100 10000 1 1 0
	./binaries/tcp_lat_epoll_with_ack.$(ARCH).elf 100 10000 1 1 0

clean:
	rm -f binaries/*$(ARCH)*elf

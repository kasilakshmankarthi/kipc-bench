#!/bin/bash

TARGET=$1
OPERATION=$2

echo "Target chosen:" ${TARGET}
echo "Operation:" ${OPERATION}

if [[ ${OPERATION} == "build" ]]; then
    make -f Makefile ARCH=${TARGET}

    mv pipe_lat                 binaries/pipe_lat.${TARGET}.elf
    mv pipe_lat_nonoverlap      binaries/pipe_lat_nonoverlap.${TARGET}.elf
    mv pipe_self_lat            binaries/pipe_self_lat.${TARGET}.elf
    mv pipe_thr                 binaries/pipe_thr.${TARGET}.elf
    mv unix_lat                 binaries/unix_lat.${TARGET}.elf
    mv unix_lat_nonoverlap      binaries/unix_lat_nonoverlap.${TARGET}.elf
    mv unix_self_lat            binaries/unix_self_lat.${TARGET}.elf
    mv unix_thr                 binaries/unix_thr.${TARGET}.elf
    mv tcp_lat                  binaries/tcp_lat.${TARGET}.elf
    mv tcp_lat_nonoverlap       binaries/tcp_lat_nonoverlap.${TARGET}.elf
    mv tcp_self_lat             binaries/tcp_self_lat.${TARGET}.elf
    mv tcp_thr                  binaries/tcp_thr.${TARGET}.elf
    mv tcp_local_lat            binaries/tcp_local_lat.${TARGET}.elf
    mv tcp_remote_lat           binaries/tcp_remote_lat.${TARGET}.elf
    mv udp_lat                  binaries/udp_lat.${TARGET}.elf
    mv tcp_lat_epoll            binaries/tcp_lat_epoll.${TARGET}.elf
    mv tcp_lat_epoll_with_ack   binaries/tcp_lat_epoll_with_ack.${TARGET}.elf

    if [[ ${TARGET} == "aarch64" ]]; then
        mv tcp_self_lat_wave   binaries/tcp_self_lat_wave.${TARGET}.elf
        mv unix_self_lat_wave  binaries/unix_self_lat_wave.${TARGET}.elf

        mv tcp_lat_wave        binaries/tcp_lat_wave.${TARGET}.elf
    fi

fi

if [[ ${OPERATION} == "run" ]]; then
    make v=1 ARCH=${TARGET} run
fi

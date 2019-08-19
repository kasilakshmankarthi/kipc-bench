kipc-bench
=========

Some very crude IPC benchmarks modified from this source: https://github.com/rigtorp/ipc-bench

ping-pong latency benchmarks:
* pipes
* unix domain sockets
* tcp sockets

throughput benchmarks:
* pipes
* unix domain sockets
* tcp sockets

This software is distributed under the MIT License.

## Commands to run ##

### Parent-Child process IPC communication ###

1. Pipe latency </br>
pipe_lat \<message-size\> \<roundtrip-count\> \<parent cpu\> \<child cpu\> \<Enable(1)/Disable(0) angel signals\></br>

Example: </br>
./binaries/pipe_lat.aarch64.elf 1500 10000 1 1 0</br>

2. Unix latency </br>
unix_lat \<message-size\> \<roundtrip-count\> \<parent cpu\> \<child cpu\> \<Enable(1)/Disable(0) angel signals\> </br>

Example: </br>
./binaries/unix_lat.aarch64.elf 1500 10000 1 1 0</br>

3. TCP/IP latency </br>
tcp_lat \<message-size\> \<roundtrip-count\> \<parent cpu\> \<child cpu\> \<Enable(1)/Disable(0) angel signals\></br>

Example:</br>
./binaries/tcp_lat.aarch64.elf 1500 10000 1 1 0</br>

### Single process IPC communication (self communicating) ###

1. Pipe self latency</br>
pipe_self_lat \<message-size\> \<roundtrip-count\> \<parent cpu\> \<Enable(1)/Disable(0) angel signals\></br>

Example:</br>
./pipe_self_lat.aarch64.elf 1500 10000 1 0</br>

2. Unix self latency</br>
unix_self_lat \<message-size\> \<roundtrip-count\> \<parent cpu\> \<Enable(1)/Disable(0) angel signals\></br>

Example:</br>
./binaries/unix_self_lat.aarch64.elf 1500 10000 1 0</br>

3. TCP/IP self latency
tcp_self_lat \<message-size\> \<roundtrip-count\> \<parent cpu\> \<Enable(1)/Disable(0) angel signals\></br>

Example:</br>
./binaries/tcp_self_lat.aarch64.elf 1500 10000 1 0</br>

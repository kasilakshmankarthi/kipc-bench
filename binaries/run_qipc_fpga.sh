ifconfig lo up

TARGET=$1
echo "Target chosen:" ${TARGET}

TYPE=$2
echo "Type chosen:" ${TYPE}

TEST=$3
echo "Test chosen (1/2) process:" ${TEST}

if [[ ${TARGET} != "" ]]; then
    if [[ ${TYPE} == "perf" ]]; then
      if [[ ${TEST} == "1" ]]; then
          #Collecting perf stat
          #######tcp_lat
          rm -rf tcp_self_lat.${TARGET}.stat
          perf stat -C 1 -e instructions,cycles ./tcp_self_lat.${TARGET}.elf 16 10000 1 0 2>tcp_self_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./tcp_self_lat.${TARGET}.elf 1500 10000 1 0 2>>tcp_self_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./tcp_self_lat.${TARGET}.elf 65536 10000 1 0 2>>tcp_self_lat.${TARGET}.stat
          echo ""

          #########unix_self_lat
          rm -rf unix_self_lat.${TARGET}.stat
          perf stat -C 1 -e instructions,cycles ./unix_self_lat.${TARGET}.elf 16 10000 1 0 2>unix_self_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./unix_self_lat.${TARGET}.elf 1500 10000 1 0 2>>unix_self_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./unix_self_lat.${TARGET}.elf 65536 10000 1 0 2>>unix_self_lat.${TARGET}.stat
          echo ""

          #########pipe_self_lat
          rm -rf pipe_self_lat.${TARGET}.stat
          perf stat -C 1 -e instructions,cycles ./pipe_self_lat.${TARGET}.elf 16 10000 1 0 2>pipe_self_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./pipe_self_lat.${TARGET}.elf 1500 10000 1 0 2>>pipe_self_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./pipe_self_lat.${TARGET}.elf 65536 10000 1 0 2>>pipe_self_lat.${TARGET}.stat
          echo ""
      else
          #Collecting perf stat
         #######tcp_lat
          rm -rf tcp_lat.${TARGET}.stat
          echo "tcp_lat"
          perf stat -C 1 -e instructions,cycles ./tcp_lat.${TARGET}.elf 16 10000 1 1 0 2>tcp_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./tcp_lat.${TARGET}.elf 1500 10000 1 1 0 2>>tcp_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./tcp_lat.${TARGET}.elf 4096 10000 1 1 0 2>>tcp_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./tcp_lat.${TARGET}.elf 8192 10000 1 1 0 2>>tcp_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./tcp_lat.${TARGET}.elf 16384 10000 1 1 0 2>>tcp_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./tcp_lat.${TARGET}.elf 32768 10000 1 1 0 2>>tcp_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./tcp_lat.${TARGET}.elf 65536 10000 1 1 0 2>>tcp_lat.${TARGET}.stat
          echo ""

          #######tcp_lat_nonoverlap
          rm -rf tcp_lat_nonoverlap.${TARGET}.stat
          echo "tcp_lat_nonoverlap"
          perf stat -C 1 -e instructions,cycles ./tcp_lat_nonoverlap.${TARGET}.elf 16 10000 1 1 0 2>tcp_lat_nonoverlap.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./tcp_lat_nonoverlap.${TARGET}.elf 1500 10000 1 1 0 2>>tcp_lat_nonoverlap.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./tcp_lat_nonoverlap.${TARGET}.elf 4096 10000 1 1 0 2>>tcp_lat_nonoverlap.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./tcp_lat_nonoverlap.${TARGET}.elf 8192 10000 1 1 0 2>>tcp_lat_nonoverlap.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./tcp_lat_nonoverlap.${TARGET}.elf 16384 10000 1 1 0 2>>tcp_lat_nonoverlap.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./tcp_lat_nonoverlap.${TARGET}.elf 32768 10000 1 1 0 2>>tcp_lat_nonoverlap.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./tcp_lat_nonoverlap.${TARGET}.elf 65536 10000 1 1 0 2>>tcp_lat_nonoverlap.${TARGET}.stat
          echo ""

          #########unix_lat
          rm -rf unix_lat.${TARGET}.stat
          echo "unix_lat"
          perf stat -C 1 -e instructions,cycles ./unix_lat.${TARGET}.elf 16 10000 1 1 0 2>unix_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./unix_lat.${TARGET}.elf 1500 10000 1 1 0 2>>unix_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./unix_lat.${TARGET}.elf 4096 10000 1 1 0 2>>unix_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./unix_lat.${TARGET}.elf 8192 10000 1 1 0 2>>unix_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./unix_lat.${TARGET}.elf 16384 10000 1 1 0 2>>unix_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./unix_lat.${TARGET}.elf 32768 10000 1 1 0 2>>unix_lat.${TARGET}.stat
          echo ""
          if [[ ${TARGET} != "x86_64" ]]; then
            perf stat -C 1 -e instructions,cycles ./unix_lat.${TARGET}.elf 65536 10000 1 1 0 2>>unix_lat.${TARGET}.stat
            echo ""
          fi

          #######unix_lat_nonoverlap
          rm -rf unix_lat_nonoverlap.${TARGET}.stat
          echo "unix_lat_nonverlap"
          perf stat -C 1 -e instructions,cycles ./unix_lat_nonoverlap.${TARGET}.elf 16 10000 1 1 0 2>unix_lat_nonoverlap.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./unix_lat_nonoverlap.${TARGET}.elf 1500 10000 1 1 0 2>>unix_lat_nonoverlap.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./unix_lat_nonoverlap.${TARGET}.elf 4096 10000 1 1 0 2>>unix_lat_nonoverlap.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./unix_lat_nonoverlap.${TARGET}.elf 8192 10000 1 1 0 2>>unix_lat_nonoverlap.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./unix_lat_nonoverlap.${TARGET}.elf 16384 10000 1 1 0 2>>unix_lat_nonoverlap.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./unix_lat_nonoverlap.${TARGET}.elf 32768 10000 1 1 0 2>>unix_lat_nonoverlap.${TARGET}.stat
          echo ""
          if [[ ${TARGET} != "x86_64" ]]; then
            perf stat -C 1 -e instructions,cycles ./unix_lat_nonoverlap.${TARGET}.elf 65536 10000 1 1 0 2>>unix_lat_nonoverlap.${TARGET}.stat
            echo ""
          fi

          #########pipe_lat
          rm -rf pipe_lat.${TARGET}.stat
          echo "pipe_lat"
          perf stat -C 1 -e instructions,cycles ./pipe_lat.${TARGET}.elf 16 10000 1 1 0 2>pipe_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./pipe_lat.${TARGET}.elf 1500 10000 1 1 0 2>>pipe_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./pipe_lat.${TARGET}.elf 4096 10000 1 1 0 2>>pipe_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./pipe_lat.${TARGET}.elf 8192 10000 1 1 0 2>>pipe_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./pipe_lat.${TARGET}.elf 16384 10000 1 1 0 2>>pipe_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./pipe_lat.${TARGET}.elf 32768 10000 1 1 0 2>>pipe_lat.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./pipe_lat.${TARGET}.elf 65536 10000 1 1 0 2>>pipe_lat.${TARGET}.stat
          echo ""

          #########pipe_lat_nonoverlap
          rm -rf pipe_lat_nonoverlap.${TARGET}.stat
          echo "pipe_lat_nonoverlap"
          perf stat -C 1 -e instructions,cycles ./pipe_lat_nonoverlap.${TARGET}.elf 16 10000 1 1 0 2>pipe_lat_nonoverlap.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./pipe_lat_nonoverlap.${TARGET}.elf 1500 10000 1 1 0 2>>pipe_lat_nonoverlap.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./pipe_lat_nonoverlap.${TARGET}.elf 4096 10000 1 1 0 2>>pipe_lat_nonoverlap.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./pipe_lat_nonoverlap.${TARGET}.elf 8192 10000 1 1 0 2>>pipe_lat_nonoverlap.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./pipe_lat_nonoverlap.${TARGET}.elf 16384 10000 1 1 0 2>>pipe_lat_nonoverlap.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./pipe_lat_nonoverlap.${TARGET}.elf 32768 10000 1 1 0 2>>pipe_lat_nonoverlap.${TARGET}.stat
          echo ""
          perf stat -C 1 -e instructions,cycles ./pipe_lat_nonoverlap.${TARGET}.elf 65536 10000 1 1 0 2>>pipe_lat_nonoverlap.${TARGET}.stat
          echo ""
       fi
   else
        #Collecting ARM PM events
        ./runAllSaphira_counters_instr_v1.sh "cp 1 2 3 4 5 6 7" "-C 1 /qipc-bench/binaries/tcp_lat.aarch64.elf 1500 10000 1 1 0" "output_tcp_lat"

        ./runAllSaphira_counters_instr_v1.sh "cp 1 2 3 4 5 6 7" "-C 1 /qipc-bench/binaries/unix_lat.aarch64.elf 1500 10000 1 1 0" "output_unix_lat"

        ./runAllSaphira_counters_instr_v1.sh "cp 1 2 3 4 5 6 7" "-C 1 /qipc-bench/binaries/pipe_lat.aarch64.elf 1500 10000 1 1 0" "output_pipe_lat"
    fi
fi

grep  "instructions" t*_lat.${TARGET}.stat | grep -Eo '[0-9,]+(\s*instructions)' | grep -Eo '[0-9,]*'
grep  "cycles" t*_lat.${TARGET}.stat | grep -Eo '[0-9,]*'
grep  "seconds time elapsed" t*_lat.${TARGET}.stat | grep -Eo '[0-9]*\.[0-9]*'

grep  "instructions" t*_lat_nonoverlap.${TARGET}.stat | grep -Eo '[0-9,]+(\s*instructions)' | grep -Eo '[0-9,]*'
grep  "cycles" t*_lat_nonoverlap.${TARGET}.stat | grep -Eo '[0-9,]*'
grep  "seconds time elapsed" t*_lat_nonoverlap.${TARGET}.stat | grep -Eo '[0-9]*\.[0-9]*'

grep  "instructions" u*_lat.${TARGET}.stat | grep -Eo '[0-9,]+(\s*instructions)' | grep -Eo '[0-9,]*'
grep  "cycles" u*_lat.${TARGET}.stat | grep -Eo '[0-9,]*'
grep  "seconds time elapsed" u*_lat.${TARGET}.stat | grep -Eo '[0-9]*\.[0-9]*'

grep  "instructions" u*_lat_nonoverlap.${TARGET}.stat | grep -Eo '[0-9,]+(\s*instructions)' | grep -Eo '[0-9,]*'
grep  "cycles" u*_lat_nonoverlap.${TARGET}.stat | grep -Eo '[0-9,]*'
grep  "seconds time elapsed" u*_lat_nonoverlap.${TARGET}.stat | grep -Eo '[0-9]*\.[0-9]*'

grep  "instructions" p*_lat.${TARGET}.stat | grep -Eo '[0-9,]+(\s*instructions)' | grep -Eo '[0-9,]*'
grep  "cycles" p*_lat.${TARGET}.stat | grep -Eo '[0-9,]*'
grep  "seconds time elapsed" p*_lat.${TARGET}.stat | grep -Eo '[0-9]*\.[0-9]*'

grep  "instructions" p*_lat_nonoverlap.${TARGET}.stat | grep -Eo '[0-9,]+(\s*instructions)' | grep -Eo '[0-9,]*'
grep  "cycles" p*_lat_nonoverlap.${TARGET}.stat | grep -Eo '[0-9,]*'
grep  "seconds time elapsed" p*_lat_nonoverlap.${TARGET}.stat | grep -Eo '[0-9]*\.[0-9]*'

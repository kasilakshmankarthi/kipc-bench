ifconfig lo up

TARGET=$1
echo "Target chosen:" ${TARGET}

TYPE=$2
echo "Type chosen:" ${TYPE}

#declare -a test=(tcp unix pipe)
test=(tcp_self unix_self pipe_self)
tSize=${#test[@]}

if [[ ${TARGET} != "" ]]; then
    if [[ ${TYPE} == "perf" ]]; then
        #Collecting perf stat
        for ((lt=0; lt<$tSize; lt++))
        do
          if [[ ${test[lt]} == *"self"* ]]; then
                rm -rf ${test[lt]}_lat.${TARGET}.stat
                perf stat -C 1 -e instructions,cycles ./${test[lt]}_lat.${TARGET}.elf 16 10000 1 0 2>>${test[lt]}_lat.${TARGET}.stat
                echo ""
                perf stat -C 1 -e instructions,cycles ./${test[lt]}_lat.${TARGET}.elf 1500 10000 1 0 2>>${test[lt]}_lat.${TARGET}.stat
                echo ""
                perf stat -C 1 -e instructions,cycles ./${test[lt]}_lat.${TARGET}.elf 65536 10000 1 0 2>>${test[lt]}_lat.${TARGET}.stat
                echo ""
           else
                rm -rf ${test[lt]}_lat.${TARGET}.stat
                perf stat -C 1 -e instructions,cycles ./${test[lt]}_lat.${TARGET}.elf 16 10000 1 1 0 2>>${test[lt]}_lat.${TARGET}.stat
                echo ""
                perf stat -C 1 -e instructions,cycles ./${test[lt]}_lat.${TARGET}.elf 1500 10000 1 1 0 2>>${test[lt]}_lat.${TARGET}.stat
                echo ""
                perf stat -C 1 -e instructions,cycles ./${test[lt]}_lat.${TARGET}.elf 65536 10000 1 1 0 2>>${test[lt]}_lat.${TARGET}.stat
                echo ""
           fi
        done
   else
        #Collecting ARM PM events
        ./runAllSaphira_counters_instr_v1.sh "cp 1 2 3 4 5 6 7" "-C 1 /qipc-bench/binaries/tcp_lat.aarch64.elf 1500 10000 1 1 0" "output_tcp_lat"

        ./runAllSaphira_counters_instr_v1.sh "cp 1 2 3 4 5 6 7" "-C 1 /qipc-bench/binaries/unix_lat.aarch64.elf 1500 10000 1 1 0" "output_unix_lat"

        ./runAllSaphira_counters_instr_v1.sh "cp 1 2 3 4 5 6 7" "-C 1 /qipc-bench/binaries/pipe_lat.aarch64.elf 1500 10000 1 1 0" "output_pipe_lat"
    fi
fi

grep  "instructions" t*_lat.${TARGET}.stat | grep -Eo '[0-9]+(\s*instructions)' | grep -Eo '[0-9]*'
grep  "cycles" t*_lat.${TARGET}.stat | grep -Eo '[0-9]*'
grep  "seconds time elapsed" t*_lat.${TARGET}.stat | grep -Eo '[0-9]*\.[0-9]*'

grep  "instructions" u*_lat.${TARGET}.stat | grep -Eo '[0-9]+(\s*instructions)' | grep -Eo '[0-9]*'
grep  "cycles" u*_lat.${TARGET}.stat | grep -Eo '[0-9]*'
grep  "seconds time elapsed" u*_lat.${TARGET}.stat | grep -Eo '[0-9]*\.[0-9]*'

grep  "instructions" p*_lat.${TARGET}.stat | grep -Eo '[0-9]+(\s*instructions)' | grep -Eo '[0-9]*'
grep  "cycles" p*_lat.${TARGET}.stat | grep -Eo '[0-9]*'
grep  "seconds time elapsed" p*_lat.${TARGET}.stat | grep -Eo '[0-9]*\.[0-9]*'

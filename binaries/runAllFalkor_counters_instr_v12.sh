#! /bin/bash
############################################################################
# 01/26/17 KBurke - added $5 arguement for user and kernel space collection
# 02/08/17 KBurke - changed arguements to allow for specific runs to take place 
# 03/05/17 KBurke - Added support to designate specific CPU,l2.l3, bus, or ddr
#                   Removed arguement that was used for grep searches (not needed)
#                   Allowed users to specify all, CP, L2, or L3 as first arguement
# 03/17/17 KBurke - Added DDR events
# 03/27/17 KBurke - Added append capability to output file while default remains 'no overwrite'
# 04/10/17 KBurke - Added check for new L2cache encoding requirement in 4.10+ kernels 
# 05/01/17 KBurke - Added echo command at end of event collection to show completion
# 08/24/17 KBurke - Added support for new qcom_pmuv3_0 names that are being phased in
# 09/01/17 KBurke - Fixed support for passing in individual index numbers
# 09/07/17 KBurke - Added some error messages from the get go and added support for l3cache_0 in anticipation
# 09/09/17 KBurke - Restored wrtie to file when looking for index list
############################################################################
#-------------------------------------------------------------------------------------------------------------------
# $1 a run count designation allowing the user to select a specific set of events to collect
#       5 would run the 5th set of events for all units (CP, L2, L3)
#       "cp 1 7 9 12" would run the 1st, 7th, 9th and 12the events for the CPU unit
#       l2 would run all the L2 event counters 
#       l3 would run all the L3 event counters
#       ddr_0_x, Where 'x' is 0 to 5 would run all ddr controller x events counters
#       "L2L3 7 9" would run the 7 and 9th events for the L2 and l3 units 
#       ALL will indicate to capture every event defined so the test better execute in a reasonable time         
#       0 would be used to output each index and its associated PMRESR descriptor code
#       -1 will return the highest index of this list
# $2 is the aplication name to run. could be something like:
#      "-C 6 taskset 0x40 app.elf args" (use quotes when necessary) - This will take care of single core execution with L2 properly isolated
#      "taskset 0x2 app.elf" - This will collect counts for where the application runs (cpu 1) but L2 counts will be sum of all L2s
#      "app.elf" - This will collect counts for wherever the application goes on a CPU and sum of all L2s
#      "-a app.elf" This will collect the sum across all CPus and all L2 
# $3 is the output file designation which can have the first word 'append' if user wants to append to an existig file
# $4 Can be 'u' or 'k' to designate user or kernel mode collection. If $4 is blank, both user and kernel mode counts wll be collected
#------------------------------------------------------------------------------------------------------------------- 

set_ddr_vars() {
   glob_ddr00=$1
   glob_ddr01=$2
   glob_ddr02=$3
   glob_ddr03=$4
   glob_ddr04=$5
   glob_ddr05=$6

   return
}

print_index() {
   #---------------------------------------------------------------
   #  $1 must be zero to print out the index description otherwise nothing happens
   #  $2 takes the form "'# pmresr descriptor"
   #  $3 is an output file name
   #---------------------------------------------------------------

   if [ $1 -eq 0 ]   # user wants to see a list of indexes
   then
      echo "index $2" >> $3
      echo "index $2"
   fi
   return
}

check_upfront_errors() {
   #---------------------------------------------------------------
   #  $1 is the arguement passed in indicates the application pre arguements for perf stat if any
   # 
   #---------------------------------------------------------------
   valid_flags=0                   # flag indicating that it is valid to collect L2 or L3 events

   perfstat_first_arg=${1%% *}     # extract first word in the string

   if [[ "$perfstat_first_arg" == "-C" || "$perfstat_first_arg" == "-a" ]]; then
      valid_flags=1
   fi


   if [ $glob_cpu -eq 1 ]; then
     if [ ! -d "/sys/bus/event_source/devices/""$glob_cpu_base" ]; then
        echo "ERROR: Cannot determine correct CPU event name to use"
        exit 99 
     fi
   fi

   if [ $glob_l2 -eq 1 ]; then
     if [ ! -d "/sys/bus/event_source/devices/""$glob_l2_base" ]; then
        echo "ERROR: Cannot determine correct L2 event name to use"
        exit 99 
     fi
     if [ $valid_flags -eq 0 ]; then
        echo "ERROR: you need to use -C or -a option for perf stat (1st word on second arguement) when collecting L2 events"
        exit 99
     fi
   fi

   if [ $glob_l3 -eq 1 ]; then
     if [ ! -d "/sys/bus/event_source/devices/""$glob_l3_base" ]; then
        echo "ERROR: Cannot determine correct L3 event name to use"
        exit 99 
     fi
     if [ $valid_flags -eq 0 ]; then
        echo "ERROR: you need to use -C or -a option for perf stat (1st word on second arguement) when collecting L3 events"
        exit 99
     fi
   fi

   return 0
}

gather_events() {
   #-------------------------------------------------------------------------------------------------------------------
   # $1 a run count designation allowing the user to select a specific set of events to collect
   #       5 would run the 5th set of events for all units (CP, L2, L3)
   #       "cp 1 7 9 12" would run the 1st, 7th, 9th and 12the events for the CPU unit
   #       l2 would run all the L2 event counters 
   #       l3 would run all the L3 event counters
   #       "L2L3 7 9" would run the 7 and 9th events for the L2 and l3 units 
   #       ALL will indicate to capture every event defined so the test better execute in a reasonable time#         
   #       0 would be used to output each index and its associated PMRESR descriptor code
   #       -1 will return the highest index of this list
   # $2 is the aplication name to run. could be something like:
   #      "-C 6 taskset 0x40 app.elf args" (use quotes when necessary) - This will take care of single core execution with L2 properly isolated
   #      "taskset 0x2 app.elf" - This will collect counts for where the application runs (cpu 1) but L2 counts will be sum of all L2s
   #      "app.elf" - This will collect counts for wherever the application goes on a CPU and sum of all L2s
   #      "-a app.elf" This will collect the sum across all CPus and all L2 
   # $3 is the output file designation
   # $4 Can be 'u' or 'k' to designate user or kernel mode collection. If $4 is blank, both user and kernel mode counts wll be collected
   #------------------------------------------------------------------------------------------------------------------- 
   event_index=1      # starting index of each event collection
   perf_needed=0
   
   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4  -e $glob_cpu_base/config=0x01/$4 -e $glob_cpu_base/config=0x2/$4  -e $glob_cpu_base/config=0x3/$4  -e $glob_cpu_base/config=0x4/$4  -e $glob_cpu_base/config=0x5/$4  -e $glob_cpu_base/config=0x6/$4  -e $glob_cpu_base/config=0x7/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         echo "#L2_GROUP Constants" >> $3
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00007/ -e $glob_l2_base/config=0x00006/ -e $glob_l2_base/config=0x00005/ -e $glob_l2_base/config=0x00004/ -e $glob_l2_base/config=0x00003/ -e $glob_l2_base/config=0x00002/ -e $glob_l2_base/config=0x00001/ -e $glob_l2_base/config=0x00000/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         echo "#L3_GROUP Internal" >> $3
         l3_events=" -e $glob_l3_base/event=0x01/ -e $glob_l3_base/event=0x02/,$glob_l3_base/event=0x40/,$glob_l3_base/event=0x41/,$glob_l3_base/event=0x42/,$glob_l3_base/event=0x43/,$glob_l3_base/event=0x44/,$glob_l3_base/event=0x45/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr00" != "${glob_ddr00/ddr/}" ]; then
         echo "#DDR_GROUP 1ST   blank" >> $3
         echo "#DDR_GROUP 1ST   blank" >> $3
         echo "#DDR_GROUP 1ST   TxSnpRslt FIFO, RCQ, WDF Full" >> $3
         ddr_events=" -e $glob_ddr00/config=127/,$glob_ddr00/config=4/,$glob_ddr00/config=7/,$glob_ddr00/config=9/,$glob_ddr00/config=10/,$glob_ddr00/config=11/,$glob_ddr00/config=12/,$glob_ddr00/config=14/,$glob_ddr00/config=19/ "
         perf_needed=1
      else
         ddr_events=" "
      fi
      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " ARMV8:0X00/L2PMRESR0:0x00/L3EVENT:0x02/$glob_ddr00:004 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index ARMV8:0X00 L2PMRESR:0x00 L3EVENT:0x02 DDR_0_1ST:004" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4  -e $glob_cpu_base/config=0x9/$4  -e $glob_cpu_base/config=0xa/$4  -e $glob_cpu_base/config=0xb/$4  -e $glob_cpu_base/config=0xc/$4  -e $glob_cpu_base/config=0xd/$4  -e $glob_cpu_base/config=0xe/$4  -e $glob_cpu_base/config=0xf/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         echo "#L2_GROUP CPU request arbitrations" >> $3
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00017/ -e $glob_l2_base/config=0x00016/ -e $glob_l2_base/config=0x00015/ -e $glob_l2_base/config=0x00014/ -e $glob_l2_base/config=0x00013/ -e $glob_l2_base/config=0x00012/ -e $glob_l2_base/config=0x00011/ -e $glob_l2_base/config=0x00010/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0x46/,$glob_l3_base/event=0x47/,$glob_l3_base/event=0x48/,$glob_l3_base/event=0x60/,$glob_l3_base/event=0x61/,$glob_l3_base/event=0x62/,$glob_l3_base/event=0x63/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr00" != "${glob_ddr00/ddr/}" ]; then
         echo "#DDR_GROUP 1ST   WDB, WBD, CBQ Reject, retry, Flushing" >> $3
         ddr_events=" -e $glob_ddr00/config=127/,$glob_ddr00/config=20/,$glob_ddr00/config=21/,$glob_ddr00/config=22/,$glob_ddr00/config=23/,$glob_ddr00/config=24/,$glob_ddr00/config=25/,$glob_ddr00/config=26/,$glob_ddr00/config=27/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " ARMV8:0X08/L2PMRESR0:0x01/L3EVENT:0x46/$glob_ddr00:020 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index ARMV8:0X08 L2PMRESR0:0x01 L3EVENT:0x46 DDR_0_1ST:020" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10/$4 -e $glob_cpu_base/config=0x11/$4 -e $glob_cpu_base/config=0x12/$4 -e $glob_cpu_base/config=0x13/$4 -e $glob_cpu_base/config=0x14/$4 -e $glob_cpu_base/config=0x15/$4 -e $glob_cpu_base/config=0x16/$4 -e $glob_cpu_base/config=0x17/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         echo "#L2_GROUP L2 hit/misss" >> $3
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00027/ -e $glob_l2_base/config=0x00026/ -e $glob_l2_base/config=0x00025/ -e $glob_l2_base/config=0x00024/ -e $glob_l2_base/config=0x00023/ -e $glob_l2_base/config=0x00022/ -e $glob_l2_base/config=0x00021/ -e $glob_l2_base/config=0x00020/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0x64/,$glob_l3_base/event=0x12/,$glob_l3_base/event=0x13/,$glob_l3_base/event=0x14/,$glob_l3_base/event=0x15/,$glob_l3_base/event=0x16/,$glob_l3_base/event=0x17/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr00" != "${glob_ddr00/ddr/}" ]; then
         ddr_events=" -e $glob_ddr00/config=127/,$glob_ddr00/config=28/,$glob_ddr00/config=29/,$glob_ddr00/config=30/,$glob_ddr00/config=31/,$glob_ddr00/config=33/,$glob_ddr00/config=36/,$glob_ddr00/config=37/,$glob_ddr00/config=38/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " ARMV8:0X10/L2PMRESR0:0x02/L3EVENT:0x64/$glob_ddr00:028 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index ARMV8:0X10 L2PMRESR0:0x02 L3EVENT:0x64 DDR_0_1ST:028" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x18/$4 -e $glob_cpu_base/config=0x19/$4 -e $glob_cpu_base/config=0x1a/$4 -e $glob_cpu_base/config=0x1b/$4 -e $glob_cpu_base/config=0x1c/$4 -e $glob_cpu_base/config=0x1d/$4 -e $glob_cpu_base/config=0x1e/$4 -e $glob_cpu_base/config=0x1f/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00037/ -e $glob_l2_base/config=0x00036/ -e $glob_l2_base/config=0x00035/ -e $glob_l2_base/config=0x00034/ -e $glob_l2_base/config=0x00033/ -e $glob_l2_base/config=0x00032/ -e $glob_l2_base/config=0x00031/ -e $glob_l2_base/config=0x00030/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         echo "#L3_GROUP L3 Request Inbound" >> $3
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0x11/,$glob_l3_base/event=0x12/,$glob_l3_base/event=0x13/,$glob_l3_base/event=0x14/,$glob_l3_base/event=0x15/,$glob_l3_base/event=0x16/,$glob_l3_base/event=0x17/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr00" != "${glob_ddr00/ddr/}" ]; then
         echo "#DDR_GROUP 1ST   CBQ BCQ, Ces, RDB" >> $3
         ddr_events=" -e $glob_ddr00/config=127/,$glob_ddr00/config=39/,$glob_ddr00/config=40/,$glob_ddr00/config=41/,$glob_ddr00/config=42/,$glob_ddr00/config=50/,$glob_ddr00/config=56/,$glob_ddr00/config=58/,$glob_ddr00/config=60/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " ARMV8:0X18/L2PMRESR0:0x03/L3EVENT:0x11/$glob_ddr00:039 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index ARMV8:0X18 L2PMRESR0:0x03 L3EVENT:0x11 DDR_0_1ST:039" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x20/$4 -e $glob_cpu_base/config=0x21/$4 -e $glob_cpu_base/config=0x22/$4 -e $glob_cpu_base/config=0x23/$4 -e $glob_cpu_base/config=0x24/$4 -e $glob_cpu_base/config=0x25/$4 -e $glob_cpu_base/config=0x26/$4 -e $glob_cpu_base/config=0x27/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         echo "#L2_GROUP CPU data return" >> $3
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00047/ -e $glob_l2_base/config=0x00046/ -e $glob_l2_base/config=0x00045/ -e $glob_l2_base/config=0x00044/ -e $glob_l2_base/config=0x00043/ -e $glob_l2_base/config=0x00042/ -e $glob_l2_base/config=0x00041/ -e $glob_l2_base/config=0x00040/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0x18/,$glob_l3_base/event=0x19/,$glob_l3_base/event=0x1a/,$glob_l3_base/event=0x1b/,$glob_l3_base/event=0x1c/,$glob_l3_base/event=0x1d/,$glob_l3_base/event=0x1e/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr00" != "${glob_ddr00/ddr/}" ]; then
         echo "#DDR_GROUP 1ST   DBE BCQx is full" >> $3
         ddr_events=" -e $glob_ddr00/config=127/,$glob_ddr00/config=68/,$glob_ddr00/config=69/,$glob_ddr00/config=70/,$glob_ddr00/config=71/,$glob_ddr00/config=72/,$glob_ddr00/config=73/,$glob_ddr00/config=74/,$glob_ddr00/config=75/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " ARMV8:0X20/L2PMRESR0:0x04/L3EVENT:0x18/$glob_ddr00:068 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index ARMV8:0X20 L2PMRESR0:0x04 L3EVENT:0x18 DDR_0_1ST:068" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x08/$4 -e $glob_cpu_base/config=0x29/$4 -e $glob_cpu_base/config=0x2a/$4 -e $glob_cpu_base/config=0x2b/$4 -e $glob_cpu_base/config=0x2c/$4 -e $glob_cpu_base/config=0x2d/$4 -e $glob_cpu_base/config=0x2e/$4 -e $glob_cpu_base/config=0x2f/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00057/ -e $glob_l2_base/config=0x00056/ -e $glob_l2_base/config=0x00055/ -e $glob_l2_base/config=0x00054/ -e $glob_l2_base/config=0x00053/ -e $glob_l2_base/config=0x00052/ -e $glob_l2_base/config=0x00051/ -e $glob_l2_base/config=0x00050/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0x1f/,$glob_l3_base/event=0x20/,$glob_l3_base/event=0x21/,$glob_l3_base/event=0x22/,$glob_l3_base/event=0x23/,$glob_l3_base/event=0x24/,$glob_l3_base/event=0x25/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr00" != "${glob_ddr00/ddr/}" ]; then
         echo "#DDR_GROUP 1ST   Read/Write/Idle Cycles" >> $3
         ddr_events=" -e $glob_ddr00/config=127/,$glob_ddr00/config=94/,$glob_ddr00/config=98/,$glob_ddr00/config=99/,$glob_ddr00/config=100/,$glob_ddr00/config=60/,$glob_ddr00/config=61/,$glob_ddr00/config=62/,$glob_ddr00/config=63/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " ARMV8:0X28/L2PMRESR0:0x05/L3EVENT:0x1F/$glob_ddr00:094 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index ARMV8:0X28 L2PMRESR0:0x05 L3EVENT:0x1F DDR_0_1ST:094" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x30/$4 -e $glob_cpu_base/config=0x31/$4 -e $glob_cpu_base/config=0x32/$4 -e $glob_cpu_base/config=0x33/$4 -e $glob_cpu_base/config=0x34/$4 -e $glob_cpu_base/config=0x35/$4 -e $glob_cpu_base/config=0x36/$4 -e $glob_cpu_base/config=0x37/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00067/ -e $glob_l2_base/config=0x00066/ -e $glob_l2_base/config=0x00065/ -e $glob_l2_base/config=0x00064/ -e $glob_l2_base/config=0x00063/ -e $glob_l2_base/config=0x00062/ -e $glob_l2_base/config=0x00061/ -e $glob_l2_base/config=0x00060/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0x70/,$glob_l3_base/event=0x73/,$glob_l3_base/event=0x30/,$glob_l3_base/event=0x31/,$glob_l3_base/event=0x32/,$glob_l3_base/event=0x33/,$glob_l3_base/event=0x34/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr00" != "${glob_ddr00/ddr/}" ]; then
         echo "#DDR_GROUP 1ST   DBE OPT x Full" >> $3
         ddr_events=" -e $glob_ddr00/config=127/,$glob_ddr00/config=101/,$glob_ddr00/config=102/,$glob_ddr00/config=103/,$glob_ddr00/config=104/,$glob_ddr00/config=106/,$glob_ddr00/config=107/,$glob_ddr00/config=108/,$glob_ddr00/config=109/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " ARMV8:0X30/L2PMRESR0:0x06/L3EVENT:0x70/$glob_ddr00:101 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index ARMV8:0X30 L2PMRESR0:0x06 L3EVENT:0x70 DDR_0_1ST:101" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP IU Basic Counts" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10007/$4 -e $glob_cpu_base/config=0x10006/$4 -e $glob_cpu_base/config=0x10005/$4 -e $glob_cpu_base/config=0x10004/$4 -e $glob_cpu_base/config=0x10003/$4 -e $glob_cpu_base/config=0x10002/$4 -e $glob_cpu_base/config=0x10001/$4 -e $glob_cpu_base/config=0x10000/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         echo "#L2_GROUP Retries" >> $3
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00077/ -e $glob_l2_base/config=0x00076/ -e $glob_l2_base/config=0x00075/ -e $glob_l2_base/config=0x00074/ -e $glob_l2_base/config=0x00073/ -e $glob_l2_base/config=0x00072/ -e $glob_l2_base/config=0x00071/ -e $glob_l2_base/config=0x00070/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         echo "#L3_GROUP Request Outbound" >> $3
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0x2e/,$glob_l3_base/event=0x2f/,$glob_l3_base/event=0x30/,$glob_l3_base/event=0x31/,$glob_l3_base/event=0x32/,$glob_l3_base/event=0x33/,$glob_l3_base/event=0x34/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr00" != "${glob_ddr00/ddr/}" ]; then
         echo "#DDR_GROUP 1ST   Thermal, Refresh, Powerdown Info" >> $3
         ddr_events=" -e $glob_ddr00/config=127/,$glob_ddr00/config=109/,$glob_ddr00/config=110/,$glob_ddr00/config=146/,$glob_ddr00/config=147/,$glob_ddr00/config=148/,$glob_ddr00/config=149/,$glob_ddr00/config=150/,$glob_ddr00/config=152/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X00/L2PMRESR0:0x07/L3EVENT:0x2E/$glob_ddr00:109 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X00 L2PMRESR0:0x07 L3EVENT:0x2E DDR_0_1ST:109" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP Cache Access Summary" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10017/$4 -e $glob_cpu_base/config=0x10016/$4 -e $glob_cpu_base/config=0x10015/$4 -e $glob_cpu_base/config=0x10014/$4 -e $glob_cpu_base/config=0x10013/$4 -e $glob_cpu_base/config=0x10012/$4 -e $glob_cpu_base/config=0x10011/$4 -e $glob_cpu_base/config=0x10010/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         echo "#L2_GROUP Internal global exclusive monitor" >> $3
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00087/ -e $glob_l2_base/config=0x00086/ -e $glob_l2_base/config=0x00085/ -e $glob_l2_base/config=0x00084/ -e $glob_l2_base/config=0x00083/ -e $glob_l2_base/config=0x00082/ -e $glob_l2_base/config=0x00081/ -e $glob_l2_base/config=0x00080/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0x35/,$glob_l3_base/event=0x36/,$glob_l3_base/event=0x37/,$glob_l3_base/event=0x38/,$glob_l3_base/event=0x3b/,$glob_l3_base/event=0x3d/,$glob_l3_base/event=0x3e/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr01" != "${glob_ddr01/ddr/}" ]; then
         echo "#DDR_GROUP 2ND  blank" >> $3
         echo "#DDR_GROUP 2ND  TxSnpRslt FIFO, RCQ, WDF Full" >> $3
         ddr_events=" -e $glob_ddr01/config=127/,$glob_ddr01/config=4/,$glob_ddr01/config=7/,$glob_ddr01/config=9/,$glob_ddr01/config=10/,$glob_ddr01/config=11/,$glob_ddr01/config=12/,$glob_ddr01/config=14/,$glob_ddr01/config=19/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X01/L2PMRESR0:0x08/L3EVENT:0x35/$glob_ddr01:004 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X01 L2PMRESR0:0x08 L3EVENT:0x35 DDR_0_2ND:004" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10027/$4 -e $glob_cpu_base/config=0x10026/$4 -e $glob_cpu_base/config=0x10025/$4 -e $glob_cpu_base/config=0x10024/$4 -e $glob_cpu_base/config=0x10023/$4 -e $glob_cpu_base/config=0x10022/$4 -e $glob_cpu_base/config=0x10021/$4 -e $glob_cpu_base/config=0x10020/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         echo "#L2_GROUP Castouts" >> $3
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00097/ -e $glob_l2_base/config=0x00096/ -e $glob_l2_base/config=0x00095/ -e $glob_l2_base/config=0x00094/ -e $glob_l2_base/config=0x00093/ -e $glob_l2_base/config=0x00092/ -e $glob_l2_base/config=0x00091/ -e $glob_l2_base/config=0x00090/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0xa0/,$glob_l3_base/event=0xa1/,$glob_l3_base/event=0xa2/,$glob_l3_base/event=0xa3/,$glob_l3_base/event=0xa5/,$glob_l3_base/event=0x58/,$glob_l3_base/event=0xb3/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr01" != "${glob_ddr01/ddr/}" ]; then
         echo "#DDR_GROUP 2ND  WDB, WBD, CBQ Reject, retry, Flushing" >> $3
         ddr_events=" -e $glob_ddr01/config=127/,$glob_ddr01/config=20/,$glob_ddr01/config=21/,$glob_ddr01/config=22/,$glob_ddr01/config=23/,$glob_ddr01/config=24/,$glob_ddr01/config=25/,$glob_ddr01/config=26/,$glob_ddr01/config=27/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X02/L2PMRESR0:0x09/L3EVENT:0xA0/$glob_ddr01:020 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X02 L2PMRESR0:0x09 L3EVENT:0xA0 DDR_0_2ND:020" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10037/$4 -e $glob_cpu_base/config=0x10036/$4 -e $glob_cpu_base/config=0x10035/$4 -e $glob_cpu_base/config=0x10034/$4 -e $glob_cpu_base/config=0x10033/$4 -e $glob_cpu_base/config=0x10032/$4 -e $glob_cpu_base/config=0x10031/$4 -e $glob_cpu_base/config=0x10030/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x000A7/ -e $glob_l2_base/config=0x000A6/ -e $glob_l2_base/config=0x000A5/ -e $glob_l2_base/config=0x000A4/ -e $glob_l2_base/config=0x000A3/ -e $glob_l2_base/config=0x000A2/ -e $glob_l2_base/config=0x000A1/ -e $glob_l2_base/config=0x000A0/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         echo "#L3_GROUP Cache" >> $3
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0x50/,$glob_l3_base/event=0x51/,$glob_l3_base/event=0x53/,$glob_l3_base/event=0x54/,$glob_l3_base/event=0x57/,$glob_l3_base/event=0x58/,$glob_l3_base/event=0xb3/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr01" != "${glob_ddr01/ddr/}" ]; then
         ddr_events=" -e $glob_ddr01/config=127/,$glob_ddr01/config=28/,$glob_ddr01/config=29/,$glob_ddr01/config=30/,$glob_ddr01/config=31/,$glob_ddr01/config=33/,$glob_ddr01/config=36/,$glob_ddr01/config=37/,$glob_ddr01/config=38/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X03/L2PMRESR0:0x0A/L3EVENT:0x50/$glob_ddr01:028 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X03 L2PMRESR0:0x0A L3EVENT:0x50 DDR_0_2ND:028" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP Full Buffers" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10087/$4 -e $glob_cpu_base/config=0x10086/$4 -e $glob_cpu_base/config=0x10085/$4 -e $glob_cpu_base/config=0x10084/$4 -e $glob_cpu_base/config=0x10083/$4 -e $glob_cpu_base/config=0x10082/$4 -e $glob_cpu_base/config=0x10081/$4 -e $glob_cpu_base/config=0x10080/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         echo "#L2_GROUP BOQ Reuse" >> $3
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x000B7/ -e $glob_l2_base/config=0x000B6/ -e $glob_l2_base/config=0x000B5/ -e $glob_l2_base/config=0x000B4/ -e $glob_l2_base/config=0x000B3/ -e $glob_l2_base/config=0x000B2/ -e $glob_l2_base/config=0x000B1/ -e $glob_l2_base/config=0x000B0/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         echo "#L3_GROUP POS" >> $3
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0x71/,$glob_l3_base/event=0x72/,$glob_l3_base/event=0x74/,$glob_l3_base/event=0x75/,$glob_l3_base/event=0xb1/,$glob_l3_base/event=0xb2/,$glob_l3_base/event=0xb3/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr01" != "${glob_ddr01/ddr/}" ]; then
         echo "#DDR_GROUP 2ND  CBQ BCQ, Ces, RDB" >> $3
         ddr_events=" -e $glob_ddr01/config=127/,$glob_ddr01/config=39/,$glob_ddr01/config=40/,$glob_ddr01/config=41/,$glob_ddr01/config=42/,$glob_ddr01/config=50/,$glob_ddr01/config=56/,$glob_ddr01/config=58/,$glob_ddr01/config=60/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X08/L2PMRESR0:0x0B/L3EVENT:0x71/$glob_ddr01:039 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X08 L2PMRESR0:0x0B L3EVENT:0x71 DDR_0_2ND:039" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP Invalidates" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x100c7/$4 -e $glob_cpu_base/config=0x100c6/$4 -e $glob_cpu_base/config=0x100c5/$4 -e $glob_cpu_base/config=0x100c4/$4 -e $glob_cpu_base/config=0x100c3/$4 -e $glob_cpu_base/config=0x100c2/$4 -e $glob_cpu_base/config=0x100c1/$4 -e $glob_cpu_base/config=0x100c0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         echo "#L2_GROUP Errors" >> $3
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x000C7/ -e $glob_l2_base/config=0x000C6/ -e $glob_l2_base/config=0x000C5/ -e $glob_l2_base/config=0x000C4/ -e $glob_l2_base/config=0x000C3/ -e $glob_l2_base/config=0x000C2/ -e $glob_l2_base/config=0x000C1/ -e $glob_l2_base/config=0x000C0/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0xb4/,$glob_l3_base/event=0xb5/,$glob_l3_base/event=0xb6/,$glob_l3_base/event=0xb7/,$glob_l3_base/event=0xb8/,$glob_l3_base/event=0xb9/,$glob_l3_base/event=0xba/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr01" != "${glob_ddr01/ddr/}" ]; then
         echo "#DDR_GROUP 2ND  DBE BCQx is full" >> $3
         ddr_events=" -e $glob_ddr01/config=127/,$glob_ddr01/config=68/,$glob_ddr01/config=69/,$glob_ddr01/config=70/,$glob_ddr01/config=71/,$glob_ddr01/config=72/,$glob_ddr01/config=73/,$glob_ddr01/config=74/,$glob_ddr01/config=75/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X0C/L2PMRESR0:0x0C/L3EVENT:0xB4/$glob_ddr01:068 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X0C L2PMRESR0:0x0C L3EVENT:0xB4 DDR_0_2ND:068" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP F1 Pipeline Movement" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10107/$4 -e $glob_cpu_base/config=0x10106/$4 -e $glob_cpu_base/config=0x10105/$4 -e $glob_cpu_base/config=0x10104/$4 -e $glob_cpu_base/config=0x10103/$4 -e $glob_cpu_base/config=0x10102/$4 -e $glob_cpu_base/config=0x10101/$4 -e $glob_cpu_base/config=0x10100/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x000D7/ -e $glob_l2_base/config=0x000D6/ -e $glob_l2_base/config=0x000D5/ -e $glob_l2_base/config=0x000D4/ -e $glob_l2_base/config=0x000D3/ -e $glob_l2_base/config=0x000D2/ -e $glob_l2_base/config=0x000D1/ -e $glob_l2_base/config=0x000D0/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0xbb/,$glob_l3_base/event=0xbc/,$glob_l3_base/event=0xbd/,$glob_l3_base/event=0xbe/,$glob_l3_base/event=0xbf/,$glob_l3_base/event=0x87/,$glob_l3_base/event=0x88/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr01" != "${glob_ddr01/ddr/}" ]; then
         echo "#DDR_GROUP 2ND  Read/Write/Idle Cycles" >> $3
         ddr_events=" -e $glob_ddr01/config=127/,$glob_ddr01/config=94/,$glob_ddr01/config=98/,$glob_ddr01/config=99/,$glob_ddr01/config=100/,$glob_ddr01/config=60/,$glob_ddr01/config=61/,$glob_ddr01/config=62/,$glob_ddr01/config=63/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X10/L2PMRESR0:0x0D/L3EVENT:0xBB/$glob_ddr01:094 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X10 L2PMRESR0:0x0D L3EVENT:0xBB DDR_0_2ND:094" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10117/$4 -e $glob_cpu_base/config=0x10116/$4 -e $glob_cpu_base/config=0x10115/$4 -e $glob_cpu_base/config=0x10114/$4 -e $glob_cpu_base/config=0x10113/$4 -e $glob_cpu_base/config=0x10112/$4 -e $glob_cpu_base/config=0x10111/$4 -e $glob_cpu_base/config=0x10110/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         echo "#L2_GROUP Livelock states" >> $3
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x000E7/ -e $glob_l2_base/config=0x000E6/ -e $glob_l2_base/config=0x000E5/ -e $glob_l2_base/config=0x000E4/ -e $glob_l2_base/config=0x000E3/ -e $glob_l2_base/config=0x000E2/ -e $glob_l2_base/config=0x000E1/ -e $glob_l2_base/config=0x000E0/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         echo "#L3_GROUP Filter,snoop" >> $3
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0x80/,$glob_l3_base/event=0x81/,$glob_l3_base/event=0x84/,$glob_l3_base/event=0x85/,$glob_l3_base/event=0x86/,$glob_l3_base/event=0x87/,$glob_l3_base/event=0x88/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr01" != "${glob_ddr01/ddr/}" ]; then
         echo "#DDR_GROUP 2ND  DBE OPT x Full" >> $3
         ddr_events=" -e $glob_ddr01/config=127/,$glob_ddr01/config=101/,$glob_ddr01/config=102/,$glob_ddr01/config=103/,$glob_ddr01/config=104/,$glob_ddr01/config=106/,$glob_ddr01/config=107/,$glob_ddr01/config=108/,$glob_ddr01/config=109/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X11/L2PMRESR0:0x0E/L3EVENT:0x80/$glob_ddr01:101 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X11 L2PMRESR0:0x0E L3EVENT:0x80 DDR_0_2ND:101" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x10126/$4 -e $glob_cpu_base/config=0x10125/$4 -e $glob_cpu_base/config=0x10124/$4 -e $glob_cpu_base/config=0x10123/$4 -e $glob_cpu_base/config=0x10122/$4 -e $glob_cpu_base/config=0x10121/$4 -e $glob_cpu_base/config=0x10120/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x000F7/ -e $glob_l2_base/config=0x000F6/ -e $glob_l2_base/config=0x000F5/ -e $glob_l2_base/config=0x000F4/ -e $glob_l2_base/config=0x000F3/ -e $glob_l2_base/config=0x000F2/ -e $glob_l2_base/config=0x000F1/ -e $glob_l2_base/config=0x000F0/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0x89/,$glob_l3_base/event=0x8c/,$glob_l3_base/event=0xc0/,$glob_l3_base/event=0xc1/,$glob_l3_base/event=0xc2/,$glob_l3_base/event=0xc3/,$glob_l3_base/event=0xd5/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr01" != "${glob_ddr01/ddr/}" ]; then
         echo "#DDR_GROUP 2ND  Thermal, Refresh, Powerdown Info" >> $3
         ddr_events=" -e $glob_ddr01/config=127/,$glob_ddr01/config=109/,$glob_ddr01/config=110/,$glob_ddr01/config=146/,$glob_ddr01/config=147/,$glob_ddr01/config=148/,$glob_ddr01/config=149/,$glob_ddr01/config=150/,$glob_ddr01/config=152/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X12/L2PMRESR0:0x0F/L3EVENT:0x89/$glob_ddr01:109 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X12 L2PMRESR0:0x0F L3EVENT:0x89 DDR_0_2ND:109" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP F2 Pipeline Movement" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10137/$4 -e $glob_cpu_base/config=0x10136/$4 -e $glob_cpu_base/config=0x10135/$4 -e $glob_cpu_base/config=0x10134/$4 -e $glob_cpu_base/config=0x10133/$4 -e $glob_cpu_base/config=0x10132/$4 -e $glob_cpu_base/config=0x10131/$4 -e $glob_cpu_base/config=0x10130/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00107/ -e $glob_l2_base/config=0x00106/ -e $glob_l2_base/config=0x00105/ -e $glob_l2_base/config=0x00104/ -e $glob_l2_base/config=0x00103/ -e $glob_l2_base/config=0x00102/ -e $glob_l2_base/config=0x00101/ -e $glob_l2_base/config=0x00100/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         echo "#L3_GROUP Snoop" >> $3
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0x8a/,$glob_l3_base/event=0x8b/,$glob_l3_base/event=0xc0/,$glob_l3_base/event=0xc1/,$glob_l3_base/event=0xc2/,$glob_l3_base/event=0xc3/,$glob_l3_base/event=0xd5/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr02" != "${glob_ddr02/ddr/}" ]; then
         echo "#DDR_GROUP 3RD blank" >> $3
         echo "#DDR_GROUP 3RD TxSnpRslt FIFO, RCQ, WDF Full" >> $3
         ddr_events=" -e $glob_ddr02/config=127/,$glob_ddr02/config=4/,$glob_ddr02/config=7/,$glob_ddr02/config=9/,$glob_ddr02/config=10/,$glob_ddr02/config=11/,$glob_ddr02/config=12/,$glob_ddr02/config=14/,$glob_ddr02/config=19/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X13/L2PMRESR0:0x10/L3EVENT:0x8A/$glob_ddr02:004 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X13 L2PMRESR0:0x10 L3EVENT:0x8A DDR_0_3RD:004" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10147/$4 -e $glob_cpu_base/config=0x10146/$4 -e $glob_cpu_base/config=0x10145/$4 -e $glob_cpu_base/config=0x10144/$4 -e $glob_cpu_base/config=0x10143/$4 -e $glob_cpu_base/config=0x10142/$4 -e $glob_cpu_base/config=0x10141/$4 -e $glob_cpu_base/config=0x10140/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         echo "#L2_GROUP HPE Generated Prefetches" >> $3
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00117/ -e $glob_l2_base/config=0x00116/ -e $glob_l2_base/config=0x00115/ -e $glob_l2_base/config=0x00114/ -e $glob_l2_base/config=0x00113/ -e $glob_l2_base/config=0x00112/ -e $glob_l2_base/config=0x00111/ -e $glob_l2_base/config=0x00110/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         echo "#L3_GROUP Power" >> $3
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0x90/,$glob_l3_base/event=0x92/,$glob_l3_base/event=0x93/,$glob_l3_base/event=0x94/,$glob_l3_base/event=0xd3/,$glob_l3_base/event=0xd4/,$glob_l3_base/event=0xd5/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr02" != "${glob_ddr02/ddr/}" ]; then
         echo "#DDR_GROUP 3RD WDB, WBD, CBQ Reject, retry, Flushing" >> $3
         ddr_events=" -e $glob_ddr02/config=127/,$glob_ddr02/config=20/,$glob_ddr02/config=21/,$glob_ddr02/config=22/,$glob_ddr02/config=23/,$glob_ddr02/config=24/,$glob_ddr02/config=25/,$glob_ddr02/config=26/,$glob_ddr02/config=27/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X14/L2PMRESR0:0x11/L3EVENT:0x90/$glob_ddr02:020 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X14 L2PMRESR0:0x11 L3EVENT:0x90 DDR_0_3RD:020" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10157/$4 -e $glob_cpu_base/config=0x10156/$4 -e $glob_cpu_base/config=0x10155/$4 -e $glob_cpu_base/config=0x10154/$4 -e $glob_cpu_base/config=0x10153/$4 -e $glob_cpu_base/config=0x10152/$4 -e $glob_cpu_base/config=0x10151/$4 -e $glob_cpu_base/config=0x10150/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00127/ -e $glob_l2_base/config=0x00126/ -e $glob_l2_base/config=0x00125/ -e $glob_l2_base/config=0x00124/ -e $glob_l2_base/config=0x00123/ -e $glob_l2_base/config=0x00122/ -e $glob_l2_base/config=0x00121/ -e $glob_l2_base/config=0x00120/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         echo "#L3_GROUP Data" >> $3
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0xa4/,$glob_l3_base/event=0xd0/,$glob_l3_base/event=0xd1/,$glob_l3_base/event=0xd2/,$glob_l3_base/event=0xd3/,$glob_l3_base/event=0xd4/,$glob_l3_base/event=0xd5/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr02" != "${glob_ddr02/ddr/}" ]; then
         ddr_events=" -e $glob_ddr02/config=127/,$glob_ddr02/config=28/,$glob_ddr02/config=29/,$glob_ddr02/config=30/,$glob_ddr02/config=31/,$glob_ddr02/config=33/,$glob_ddr02/config=36/,$glob_ddr02/config=37/,$glob_ddr02/config=38/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X15/L2PMRESR0:0x12/L3EVENT:0xA4/$glob_ddr02:028 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X15 L2PMRESR0:0x12 L3EVENT:0xA4 DDR_0_3RD:028" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP F3 Pipeline Movement" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10207/$4 -e $glob_cpu_base/config=0x10206/$4 -e $glob_cpu_base/config=0x10205/$4 -e $glob_cpu_base/config=0x10204/$4 -e $glob_cpu_base/config=0x10203/$4 -e $glob_cpu_base/config=0x10202/$4 -e $glob_cpu_base/config=0x10201/$4 -e $glob_cpu_base/config=0x10200/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00137/ -e $glob_l2_base/config=0x00136/ -e $glob_l2_base/config=0x00135/ -e $glob_l2_base/config=0x00134/ -e $glob_l2_base/config=0x00133/ -e $glob_l2_base/config=0x00132/ -e $glob_l2_base/config=0x00131/ -e $glob_l2_base/config=0x00130/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0xd6/,$glob_l3_base/event=0xd7/,$glob_l3_base/event=0xd8/,$glob_l3_base/event=0xd9/,$glob_l3_base/event=0xda/,$glob_l3_base/event=0xdb/,$glob_l3_base/event=0xdc/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr02" != "${glob_ddr02/ddr/}" ]; then
         echo "#DDR_GROUP 3RD CBQ BCQ, Ces, RDB" >> $3
         ddr_events=" -e $glob_ddr02/config=127/,$glob_ddr02/config=39/,$glob_ddr02/config=40/,$glob_ddr02/config=41/,$glob_ddr02/config=42/,$glob_ddr02/config=50/,$glob_ddr02/config=56/,$glob_ddr02/config=58/,$glob_ddr02/config=60/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X20/L2PMRESR0:0x13/L3EVENT:0xD6/$glob_ddr02:039 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X20 L2PMRESR0:0x13 L3EVENT:0xD6 DDR_0_3RD:039" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10217/$4 -e $glob_cpu_base/config=0x10216/$4 -e $glob_cpu_base/config=0x10215/$4 -e $glob_cpu_base/config=0x10214/$4 -e $glob_cpu_base/config=0x10213/$4 -e $glob_cpu_base/config=0x10212/$4 -e $glob_cpu_base/config=0x10211/$4 -e $glob_cpu_base/config=0x10210/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         echo "#L2_GROUP Types of CPU requests" >> $3
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00407/ -e $glob_l2_base/config=0x00406/ -e $glob_l2_base/config=0x00405/ -e $glob_l2_base/config=0x00404/ -e $glob_l2_base/config=0x00403/ -e $glob_l2_base/config=0x00402/ -e $glob_l2_base/config=0x00401/ -e $glob_l2_base/config=0x00400/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ $glob_l3 -eq 1 ]; then
         echo "#L3_GROUP Data+Error+Power" >> $3
         l3_events=" -e $glob_l3_base/event=0x01/,$glob_l3_base/event=0xdd/,$glob_l3_base/event=0xed/,$glob_l3_base/event=0xee/,$glob_l3_base/event=0x90/,$glob_l3_base/event=0x92/,$glob_l3_base/event=0x93/,$glob_l3_base/event=0x94/ "
         perf_needed=1
      else
         l3_events=" "
      fi
      if [ "$glob_ddr02" != "${glob_ddr02/ddr/}" ]; then
         echo "#DDR_GROUP 3RD DBE BCQx is full" >> $3
         ddr_events=" -e $glob_ddr02/config=127/,$glob_ddr02/config=68/,$glob_ddr02/config=69/,$glob_ddr02/config=70/,$glob_ddr02/config=71/,$glob_ddr02/config=72/,$glob_ddr02/config=73/,$glob_ddr02/config=74/,$glob_ddr02/config=75/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X21/L2PMRESR0:0x40/L3EVENT:0xDD/$glob_ddr02:068 " $cp_events $l2_events $l3_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X21 L2PMRESR0:0x40 L3EVENT:0xDD DDR_0_3RD:068" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10227/$4 -e $glob_cpu_base/config=0x10226/$4 -e $glob_cpu_base/config=0x10225/$4 -e $glob_cpu_base/config=0x10224/$4 -e $glob_cpu_base/config=0x10223/$4 -e $glob_cpu_base/config=0x10222/$4 -e $glob_cpu_base/config=0x10221/$4 -e $glob_cpu_base/config=0x10220/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00417/ -e $glob_l2_base/config=0x00416/ -e $glob_l2_base/config=0x00415/ -e $glob_l2_base/config=0x00414/ -e $glob_l2_base/config=0x00413/ -e $glob_l2_base/config=0x00412/ -e $glob_l2_base/config=0x00411/ -e $glob_l2_base/config=0x00410/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ "$glob_ddr02" != "${glob_ddr02/ddr/}" ]; then
         echo "#DDR_GROUP 3RD Read/Write/Idle Cycles" >> $3
         ddr_events=" -e $glob_ddr02/config=127/,$glob_ddr02/config=94/,$glob_ddr02/config=98/,$glob_ddr02/config=99/,$glob_ddr02/config=100/,$glob_ddr02/config=60/,$glob_ddr02/config=61/,$glob_ddr02/config=62/,$glob_ddr02/config=63/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X22/L2PMRESR0:0x41/$glob_ddr02:094 " $cp_events $l2_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X22 L2PMRESR0:0x41 DDR_0_3RD:094" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10237/$4 -e $glob_cpu_base/config=0x10236/$4 -e $glob_cpu_base/config=0x10235/$4 -e $glob_cpu_base/config=0x10234/$4 -e $glob_cpu_base/config=0x10233/$4 -e $glob_cpu_base/config=0x10232/$4 -e $glob_cpu_base/config=0x10231/$4 -e $glob_cpu_base/config=0x10230/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00427/ -e $glob_l2_base/config=0x00426/ -e $glob_l2_base/config=0x00425/ -e $glob_l2_base/config=0x00424/ -e $glob_l2_base/config=0x00423/ -e $glob_l2_base/config=0x00422/ -e $glob_l2_base/config=0x00421/ -e $glob_l2_base/config=0x00420/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ "$glob_ddr02" != "${glob_ddr02/ddr/}" ]; then
         echo "#DDR_GROUP 3RD DBE OPT x Full" >> $3
         ddr_events=" -e $glob_ddr02/config=127/,$glob_ddr02/config=101/,$glob_ddr02/config=102/,$glob_ddr02/config=103/,$glob_ddr02/config=104/,$glob_ddr02/config=106/,$glob_ddr02/config=107/,$glob_ddr02/config=108/,$glob_ddr02/config=109/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X23/L2PMRESR0:0x42/$glob_ddr02:101 " $cp_events $l2_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X23 L2PMRESR0:0x42 DDR_0_3RD:101" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP HOptimizations" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10267/$4 -e $glob_cpu_base/config=0x10266/$4 -e $glob_cpu_base/config=0x10265/$4 -e $glob_cpu_base/config=0x10264/$4 -e $glob_cpu_base/config=0x10263/$4 -e $glob_cpu_base/config=0x10262/$4 -e $glob_cpu_base/config=0x10261/$4 -e $glob_cpu_base/config=0x10260/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00437/ -e $glob_l2_base/config=0x00436/ -e $glob_l2_base/config=0x00435/ -e $glob_l2_base/config=0x00434/ -e $glob_l2_base/config=0x00433/ -e $glob_l2_base/config=0x00432/ -e $glob_l2_base/config=0x00431/ -e $glob_l2_base/config=0x00430/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ "$glob_ddr02" != "${glob_ddr02/ddr/}" ]; then
         echo "#DDR_GROUP 3RD Thermal, Refresh, Powerdown Info" >> $3
         ddr_events=" -e $glob_ddr02/config=127/,$glob_ddr02/config=109/,$glob_ddr02/config=110/,$glob_ddr02/config=146/,$glob_ddr02/config=147/,$glob_ddr02/config=148/,$glob_ddr02/config=149/,$glob_ddr02/config=150/,$glob_ddr02/config=152/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X26/L2PMRESR0:0x43/$glob_ddr02:109 " $cp_events $l2_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X26 L2PMRESR0:0x43 DDR_0_3RD:109" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP IQ Pipeline Movement" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10307/$4 -e $glob_cpu_base/config=0x10306/$4 -e $glob_cpu_base/config=0x10305/$4 -e $glob_cpu_base/config=0x10304/$4 -e $glob_cpu_base/config=0x10303/$4 -e $glob_cpu_base/config=0x10302/$4 -e $glob_cpu_base/config=0x10301/$4 -e $glob_cpu_base/config=0x10300/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00447/ -e $glob_l2_base/config=0x00446/ -e $glob_l2_base/config=0x00445/ -e $glob_l2_base/config=0x00444/ -e $glob_l2_base/config=0x00443/ -e $glob_l2_base/config=0x00442/ -e $glob_l2_base/config=0x00441/ -e $glob_l2_base/config=0x00440/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ "$glob_ddr03" != "${glob_ddr03/ddr/}" ]; then
         echo "#DDR_GROUP 4TH blank" >> $3
         echo "#DDR_GROUP 4TH TxSnpRslt FIFO, RCQ, WDF Full" >> $3
         ddr_events=" -e $glob_ddr03/config=127/,$glob_ddr03/config=4/,$glob_ddr03/config=7/,$glob_ddr03/config=9/,$glob_ddr03/config=10/,$glob_ddr03/config=11/,$glob_ddr03/config=12/,$glob_ddr03/config=14/,$glob_ddr03/config=19/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X30/L2PMRESR0:0x44/$glob_ddr03:004 " $cp_events $l2_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X30 L2PMRESR0:0x44 DDR_0_4TH:004" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP Operating Modes" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10407/$4 -e $glob_cpu_base/config=0x10406/$4 -e $glob_cpu_base/config=0x10405/$4 -e $glob_cpu_base/config=0x10404/$4 -e $glob_cpu_base/config=0x10403/$4 -e $glob_cpu_base/config=0x10402/$4 -e $glob_cpu_base/config=0x10401/$4 -e $glob_cpu_base/config=0x10400/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         echo "#L2_GROUP Types of snoop requests targeting a CPU" >> $3
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00457/ -e $glob_l2_base/config=0x00456/ -e $glob_l2_base/config=0x00455/ -e $glob_l2_base/config=0x00454/ -e $glob_l2_base/config=0x00453/ -e $glob_l2_base/config=0x00452/ -e $glob_l2_base/config=0x00451/ -e $glob_l2_base/config=0x00450/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ "$glob_ddr03" != "${glob_ddr03/ddr/}" ]; then
         echo "#DDR_GROUP 4TH WDB, WBD, CBQ Reject, retry, Flushing" >> $3
         ddr_events=" -e $glob_ddr03/config=127/,$glob_ddr03/config=20/,$glob_ddr03/config=21/,$glob_ddr03/config=22/,$glob_ddr03/config=23/,$glob_ddr03/config=24/,$glob_ddr03/config=25/,$glob_ddr03/config=26/,$glob_ddr03/config=27/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X40/L2PMRESR0:0x45/$glob_ddr03:020 " $cp_events $l2_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X40 L2PMRESR0:0x45 DDR_0_4TH:020" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x10416/$4 -e $glob_cpu_base/config=0x10415/$4 -e $glob_cpu_base/config=0x10414/$4 -e $glob_cpu_base/config=0x10413/$4 -e $glob_cpu_base/config=0x10412/$4 -e $glob_cpu_base/config=0x10411/$4 -e $glob_cpu_base/config=0x10410/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00467/ -e $glob_l2_base/config=0x00466/ -e $glob_l2_base/config=0x00465/ -e $glob_l2_base/config=0x00464/ -e $glob_l2_base/config=0x00463/ -e $glob_l2_base/config=0x00462/ -e $glob_l2_base/config=0x00461/ -e $glob_l2_base/config=0x00460/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ "$glob_ddr03" != "${glob_ddr03/ddr/}" ]; then
         ddr_events=" -e $glob_ddr03/config=127/,$glob_ddr03/config=28/,$glob_ddr03/config=29/,$glob_ddr03/config=30/,$glob_ddr03/config=31/,$glob_ddr03/config=33/,$glob_ddr03/config=36/,$glob_ddr03/config=37/,$glob_ddr03/config=38/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X41/L2PMRESR0:0x46/$glob_ddr03:028 " $cp_events $l2_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X41 L2PMRESR0:0x46 DDR_0_4TH:028" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP asynchronous interrupts" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x10456/$4 -e $glob_cpu_base/config=0x10455/$4 -e $glob_cpu_base/config=0x10454/$4 -e $glob_cpu_base/config=0x10453/$4 -e $glob_cpu_base/config=0x10452/$4 -e $glob_cpu_base/config=0x10451/$4 -e $glob_cpu_base/config=0x10450/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00477/ -e $glob_l2_base/config=0x00476/ -e $glob_l2_base/config=0x00475/ -e $glob_l2_base/config=0x00474/ -e $glob_l2_base/config=0x00473/ -e $glob_l2_base/config=0x00472/ -e $glob_l2_base/config=0x00471/ -e $glob_l2_base/config=0x00470/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ "$glob_ddr03" != "${glob_ddr03/ddr/}" ]; then
         echo "#DDR_GROUP 4TH CBQ BCQ, Ces, RDB" >> $3
         ddr_events=" -e $glob_ddr03/config=127/,$glob_ddr03/config=39/,$glob_ddr03/config=40/,$glob_ddr03/config=41/,$glob_ddr03/config=42/,$glob_ddr03/config=50/,$glob_ddr03/config=56/,$glob_ddr03/config=58/,$glob_ddr03/config=60/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X45/L2PMRESR0:0x47/$glob_ddr03:039 " $cp_events $l2_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X45 L2PMRESR0:0x47 DDR_0_4TH:039" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10467/$4 -e $glob_cpu_base/config=0x10466/$4 -e $glob_cpu_base/config=0x10465/$4 -e $glob_cpu_base/config=0x10464/$4 -e $glob_cpu_base/config=0x10463/$4 -e $glob_cpu_base/config=0x10462/$4 -e $glob_cpu_base/config=0x10461/$4 -e $glob_cpu_base/config=0x10460/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00487/ -e $glob_l2_base/config=0x00486/ -e $glob_l2_base/config=0x00485/ -e $glob_l2_base/config=0x00484/ -e $glob_l2_base/config=0x00483/ -e $glob_l2_base/config=0x00482/ -e $glob_l2_base/config=0x00481/ -e $glob_l2_base/config=0x00480/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ "$glob_ddr03" != "${glob_ddr03/ddr/}" ]; then
         echo "#DDR_GROUP 4TH DBE BCQx is full" >> $3
         ddr_events=" -e $glob_ddr03/config=127/,$glob_ddr03/config=68/,$glob_ddr03/config=69/,$glob_ddr03/config=70/,$glob_ddr03/config=71/,$glob_ddr03/config=72/,$glob_ddr03/config=73/,$glob_ddr03/config=74/,$glob_ddr03/config=75/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X46/L2PMRESR0:0x48/$glob_ddr03:068 " $cp_events $l2_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X46 L2PMRESR0:0x48 DDR_0_4TH:068" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP Synchronous exceptions Taken to AArch64" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x104B7/$4 -e $glob_cpu_base/config=0x104B6/$4 -e $glob_cpu_base/config=0x104B5/$4 -e $glob_cpu_base/config=0x104B4/$4 -e $glob_cpu_base/config=0x104B3/$4 -e $glob_cpu_base/config=0x104B2/$4 -e $glob_cpu_base/config=0x104B1/$4 -e $glob_cpu_base/config=0x104B0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00497/ -e $glob_l2_base/config=0x00496/ -e $glob_l2_base/config=0x00495/ -e $glob_l2_base/config=0x00494/ -e $glob_l2_base/config=0x00493/ -e $glob_l2_base/config=0x00492/ -e $glob_l2_base/config=0x00491/ -e $glob_l2_base/config=0x00490/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ "$glob_ddr03" != "${glob_ddr03/ddr/}" ]; then
         echo "#DDR_GROUP 4TH Read/Write/Idle Cycles" >> $3
         ddr_events=" -e $glob_ddr03/config=127/,$glob_ddr03/config=94/,$glob_ddr03/config=98/,$glob_ddr03/config=99/,$glob_ddr03/config=100/,$glob_ddr03/config=60/,$glob_ddr03/config=61/,$glob_ddr03/config=62/,$glob_ddr03/config=63/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X4B/L2PMRESR0:0x49/$glob_ddr03:094 " $cp_events $l2_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X4B L2PMRESR0:0x49 DDR_0_4TH:094" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x104C7/$4 -e $glob_cpu_base/config=0x104C6/$4 -e $glob_cpu_base/config=0x104C5/$4 -e $glob_cpu_base/config=0x104C4/$4 -e $glob_cpu_base/config=0x104C3/$4 -e $glob_cpu_base/config=0x104C2/$4 -e $glob_cpu_base/config=0x104C1/$4 -e $glob_cpu_base/config=0x104C0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x004A7/ -e $glob_l2_base/config=0x004A6/ -e $glob_l2_base/config=0x004A5/ -e $glob_l2_base/config=0x004A4/ -e $glob_l2_base/config=0x004A3/ -e $glob_l2_base/config=0x004A2/ -e $glob_l2_base/config=0x004A1/ -e $glob_l2_base/config=0x004A0/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ "$glob_ddr03" != "${glob_ddr03/ddr/}" ]; then
         echo "#DDR_GROUP 4TH DBE OPT x Full" >> $3
         ddr_events=" -e $glob_ddr03/config=127/,$glob_ddr03/config=101/,$glob_ddr03/config=102/,$glob_ddr03/config=103/,$glob_ddr03/config=104/,$glob_ddr03/config=106/,$glob_ddr03/config=107/,$glob_ddr03/config=108/,$glob_ddr03/config=109/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X4C/L2PMRESR0:0x4A/$glob_ddr03:101 " $cp_events $l2_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X4C L2PMRESR0:0x4A DDR_0_4TH:101" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x104D7/$4 -e $glob_cpu_base/config=0x104D6/$4 -e $glob_cpu_base/config=0x104D5/$4 -e $glob_cpu_base/config=0x104D4/$4 -e $glob_cpu_base/config=0x104D3/$4 -e $glob_cpu_base/config=0x104D2/$4 -e $glob_cpu_base/config=0x104D1/$4 -e $glob_cpu_base/config=0x104D0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         echo "#L2_GROUP Mastered bus command types" >> $3
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00607/ -e $glob_l2_base/config=0x00606/ -e $glob_l2_base/config=0x00605/ -e $glob_l2_base/config=0x00604/ -e $glob_l2_base/config=0x00603/ -e $glob_l2_base/config=0x00602/ -e $glob_l2_base/config=0x00601/ -e $glob_l2_base/config=0x00600/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ "$glob_ddr03" != "${glob_ddr03/ddr/}" ]; then
         echo "#DDR_GROUP 4TH Thermal, Refresh, Powerdown Info" >> $3
         ddr_events=" -e $glob_ddr03/config=127/,$glob_ddr03/config=109/,$glob_ddr03/config=110/,$glob_ddr03/config=146/,$glob_ddr03/config=147/,$glob_ddr03/config=148/,$glob_ddr03/config=149/,$glob_ddr03/config=150/,$glob_ddr03/config=152/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X4D/L2PMRESR0:0x60/$glob_ddr03:109 " $cp_events $l2_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X4D L2PMRESR0:0x60 DDR_0_4TH:109" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP ERRORS" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10507/$4 -e $glob_cpu_base/config=0x10506/$4 -e $glob_cpu_base/config=0x10505/$4 -e $glob_cpu_base/config=0x10504/$4 -e $glob_cpu_base/config=0x10503/$4 -e $glob_cpu_base/config=0x10502/$4 -e $glob_cpu_base/config=0x10501/$4 -e $glob_cpu_base/config=0x10500/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00617/ -e $glob_l2_base/config=0x00616/ -e $glob_l2_base/config=0x00615/ -e $glob_l2_base/config=0x00614/ -e $glob_l2_base/config=0x00613/ -e $glob_l2_base/config=0x00612/ -e $glob_l2_base/config=0x00611/ -e $glob_l2_base/config=0x00610/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ "$glob_ddr04" != "${glob_ddr04/ddr/}" ]; then
         echo "#DDR_GROUP 5TH blank" >> $3
         echo "#DDR_GROUP 5TH TxSnpRslt FIFO, RCQ, WDF Full" >> $3
         ddr_events=" -e $glob_ddr04/config=127/,$glob_ddr04/config=4/,$glob_ddr04/config=7/,$glob_ddr04/config=9/,$glob_ddr04/config=10/,$glob_ddr04/config=11/,$glob_ddr04/config=12/,$glob_ddr04/config=14/,$glob_ddr04/config=19/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X50/L2PMRESR0:0x61/$glob_ddr04:004 " $cp_events $l2_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X50 L2PMRESR0:0x61 DDR_0_5TH:004" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10517/$4 -e $glob_cpu_base/config=0x10516/$4 -e $glob_cpu_base/config=0x10515/$4 -e $glob_cpu_base/config=0x10514/$4 -e $glob_cpu_base/config=0x10513/$4 -e $glob_cpu_base/config=0x10512/$4 -e $glob_cpu_base/config=0x10511/$4 -e $glob_cpu_base/config=0x10510/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         echo "#L2_GROUP Results for mastered bus commands" >> $3
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00627/ -e $glob_l2_base/config=0x00626/ -e $glob_l2_base/config=0x00625/ -e $glob_l2_base/config=0x00624/ -e $glob_l2_base/config=0x00623/ -e $glob_l2_base/config=0x00622/ -e $glob_l2_base/config=0x00621/ -e $glob_l2_base/config=0x00620/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ "$glob_ddr04" != "${glob_ddr04/ddr/}" ]; then
         echo "#DDR_GROUP 5TH WDB, WBD, CBQ Reject, retry, Flushing" >> $3
         ddr_events=" -e $glob_ddr04/config=127/,$glob_ddr04/config=20/,$glob_ddr04/config=21/,$glob_ddr04/config=22/,$glob_ddr04/config=23/,$glob_ddr04/config=24/,$glob_ddr04/config=25/,$glob_ddr04/config=26/,$glob_ddr04/config=27/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X51/L2PMRESR0:0x62/$glob_ddr04:020 " $cp_events $l2_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X51 L2PMRESR0:0x62 DDR_0_5TH:020" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP General GIC Events" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x10526/$4 -e $glob_cpu_base/config=0x10525/$4 -e $glob_cpu_base/config=0x10524/$4 -e $glob_cpu_base/config=0x10523/$4 -e $glob_cpu_base/config=0x10522/$4 -e $glob_cpu_base/config=0x10521/$4 -e $glob_cpu_base/config=0x10520/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         echo "#L2_GROUP Bus latencies" >> $3 
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00637/ -e $glob_l2_base/config=0x00636/ -e $glob_l2_base/config=0x00635/ -e $glob_l2_base/config=0x00634/ -e $glob_l2_base/config=0x00633/ -e $glob_l2_base/config=0x00632/ -e $glob_l2_base/config=0x00631/ -e $glob_l2_base/config=0x00630/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ "$glob_ddr04" != "${glob_ddr04/ddr/}" ]; then
         ddr_events=" -e $glob_ddr04/config=127/,$glob_ddr04/config=28/,$glob_ddr04/config=29/,$glob_ddr04/config=30/,$glob_ddr04/config=31/,$glob_ddr04/config=33/,$glob_ddr04/config=36/,$glob_ddr04/config=37/,$glob_ddr04/config=38/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X52/L2PMRESR0:0x63/$glob_ddr04:028 " $cp_events $l2_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X52 L2PMRESR0:0x63 DDR_0_5TH:028" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP GIC Maintenance Interrupts" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10557/$4 -e $glob_cpu_base/config=0x10556/$4 -e $glob_cpu_base/config=0x10555/$4 -e $glob_cpu_base/config=0x10554/$4 -e $glob_cpu_base/config=0x10553/$4 -e $glob_cpu_base/config=0x10552/$4 -e $glob_cpu_base/config=0x10551/$4 -e $glob_cpu_base/config=0x10550/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00647/ -e $glob_l2_base/config=0x00646/ -e $glob_l2_base/config=0x00645/ -e $glob_l2_base/config=0x00644/ -e $glob_l2_base/config=0x00643/ -e $glob_l2_base/config=0x00642/ -e $glob_l2_base/config=0x00641/ -e $glob_l2_base/config=0x00640/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ "$glob_ddr04" != "${glob_ddr04/ddr/}" ]; then
         echo "#DDR_GROUP 5TH CBQ BCQ, Ces, RDB" >> $3
         ddr_events=" -e $glob_ddr04/config=127/,$glob_ddr04/config=39/,$glob_ddr04/config=40/,$glob_ddr04/config=41/,$glob_ddr04/config=42/,$glob_ddr04/config=50/,$glob_ddr04/config=56/,$glob_ddr04/config=58/,$glob_ddr04/config=60/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X55/L2PMRESR0:0x64/$glob_ddr04:039 " $cp_events $l2_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X55 L2PMRESR0:0x64 DDR_0_5TH:039" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP GIC Packets Received/Sent" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x10586/$4 -e $glob_cpu_base/config=0x10585/$4 -e $glob_cpu_base/config=0x10584/$4 -e $glob_cpu_base/config=0x10583/$4 -e $glob_cpu_base/config=0x10582/$4 -e $glob_cpu_base/config=0x10581/$4 -e $glob_cpu_base/config=0x10580/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         echo "#L2_GROUP Snoop Requests" >> $3
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00657/ -e $glob_l2_base/config=0x00656/ -e $glob_l2_base/config=0x00655/ -e $glob_l2_base/config=0x00654/ -e $glob_l2_base/config=0x00653/ -e $glob_l2_base/config=0x00652/ -e $glob_l2_base/config=0x00651/ -e $glob_l2_base/config=0x00650/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ "$glob_ddr04" != "${glob_ddr04/ddr/}" ]; then
         echo "#DDR_GROUP 5TH DBE BCQx is full" >> $3
         ddr_events=" -e $glob_ddr04/config=127/,$glob_ddr04/config=68/,$glob_ddr04/config=69/,$glob_ddr04/config=70/,$glob_ddr04/config=71/,$glob_ddr04/config=72/,$glob_ddr04/config=73/,$glob_ddr04/config=74/,$glob_ddr04/config=75/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X58/L2PMRESR0:0x65/$glob_ddr04:068 " $cp_events $l2_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X58 L2PMRESR0:0x65 DDR_0_5TH:068" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10597/$4 -e $glob_cpu_base/config=0x10596/$4 -e $glob_cpu_base/config=0x10595/$4 -e $glob_cpu_base/config=0x10594/$4 -e $glob_cpu_base/config=0x10593/$4 -e $glob_cpu_base/config=0x10592/$4 -e $glob_cpu_base/config=0x10591/$4 -e $glob_cpu_base/config=0x10590/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00667/ -e $glob_l2_base/config=0x00666/ -e $glob_l2_base/config=0x00665/ -e $glob_l2_base/config=0x00664/ -e $glob_l2_base/config=0x00663/ -e $glob_l2_base/config=0x00662/ -e $glob_l2_base/config=0x00661/ -e $glob_l2_base/config=0x00660/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ "$glob_ddr04" != "${glob_ddr04/ddr/}" ]; then
         echo "#DDR_GROUP 5TH Read/Write/Idle Cycles" >> $3
         ddr_events=" -e $glob_ddr04/config=127/,$glob_ddr04/config=94/,$glob_ddr04/config=98/,$glob_ddr04/config=99/,$glob_ddr04/config=100/,$glob_ddr04/config=60/,$glob_ddr04/config=61/,$glob_ddr04/config=62/,$glob_ddr04/config=63/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X59/L2PMRESR0:0x66/$glob_ddr04:094 " $cp_events $l2_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X59 L2PMRESR0:0x66 DDR_0_5TH:094" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x105A7/$4 -e $glob_cpu_base/config=0x105A6/$4 -e $glob_cpu_base/config=0x105A5/$4 -e $glob_cpu_base/config=0x105A4/$4 -e $glob_cpu_base/config=0x105A3/$4 -e $glob_cpu_base/config=0x105A2/$4 -e $glob_cpu_base/config=0x105A1/$4 -e $glob_cpu_base/config=0x105A0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         echo "#L2_GROUP Sleep States" >> $3
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00807/ -e $glob_l2_base/config=0x00806/ -e $glob_l2_base/config=0x00805/ -e $glob_l2_base/config=0x00804/ -e $glob_l2_base/config=0x00803/ -e $glob_l2_base/config=0x00802/ -e $glob_l2_base/config=0x00801/ -e $glob_l2_base/config=0x00800/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ "$glob_ddr04" != "${glob_ddr04/ddr/}" ]; then
         echo "#DDR_GROUP 5TH DBE OPT x Full" >> $3
         ddr_events=" -e $glob_ddr04/config=127/,$glob_ddr04/config=101/,$glob_ddr04/config=102/,$glob_ddr04/config=103/,$glob_ddr04/config=104/,$glob_ddr04/config=106/,$glob_ddr04/config=107/,$glob_ddr04/config=108/,$glob_ddr04/config=109/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X5A/L2PMRESR0:0x80/$glob_ddr04:101 " $cp_events $l2_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X5A L2PMRESR0:0x80 DDR_0_5TH:101" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP Branch Prediction (Direction)" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x10606/$4 -e $glob_cpu_base/config=0x10605/$4 -e $glob_cpu_base/config=0x10604/$4 -e $glob_cpu_base/config=0x10603/$4 -e $glob_cpu_base/config=0x10602/$4 -e $glob_cpu_base/config=0x10601/$4 -e $glob_cpu_base/config=0x10600/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ $glob_l2 -eq 1 ]; then
         l2_events=" -e $glob_l2_base/config=0x000FE/ -e $glob_l2_base/config=0x00817/ -e $glob_l2_base/config=0x00816/ -e $glob_l2_base/config=0x00815/ -e $glob_l2_base/config=0x00814/ -e $glob_l2_base/config=0x00813/ -e $glob_l2_base/config=0x00812/ -e $glob_l2_base/config=0x00811/ -e $glob_l2_base/config=0x00810/ "
         perf_needed=1
      else
         l2_events=" "
      fi
      if [ "$glob_ddr04" != "${glob_ddr04/ddr/}" ]; then
         echo "#DDR_GROUP 5TH Thermal, Refresh, Powerdown Info" >> $3
         ddr_events=" -e $glob_ddr04/config=127/,$glob_ddr04/config=109/,$glob_ddr04/config=110/,$glob_ddr04/config=146/,$glob_ddr04/config=147/,$glob_ddr04/config=148/,$glob_ddr04/config=149/,$glob_ddr04/config=150/,$glob_ddr04/config=152/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X60/L2PMRESR0:0x81/$glob_ddr04:109 " $cp_events $l2_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X60 L2PMRESR0:0x81 DDR_0_5TH:109" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10617/$4 -e $glob_cpu_base/config=0x10616/$4 -e $glob_cpu_base/config=0x10615/$4 -e $glob_cpu_base/config=0x10614/$4 -e $glob_cpu_base/config=0x10613/$4 -e $glob_cpu_base/config=0x10612/$4 -e $glob_cpu_base/config=0x10611/$4 -e $glob_cpu_base/config=0x10610/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ "$glob_ddr05" != "${glob_ddr05/ddr/}" ]; then
         echo "#DDR_GROUP 6TH  blank" >> $3
         echo "#DDR_GROUP 6TH  TxSnpRslt FIFO, RCQ, WDF Full" >> $3
         ddr_events=" -e $glob_ddr05/config=127/,$glob_ddr05/config=4/,$glob_ddr05/config=7/,$glob_ddr05/config=9/,$glob_ddr05/config=10/,$glob_ddr05/config=11/,$glob_ddr05/config=12/,$glob_ddr05/config=14/,$glob_ddr05/config=19/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X61/$glob_ddr05:004 " $cp_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X61 DDR_0_6TH:004" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10627/$4 -e $glob_cpu_base/config=0x10626/$4 -e $glob_cpu_base/config=0x10625/$4 -e $glob_cpu_base/config=0x10624/$4 -e $glob_cpu_base/config=0x10623/$4 -e $glob_cpu_base/config=0x10622/$4 -e $glob_cpu_base/config=0x10621/$4 -e $glob_cpu_base/config=0x10620/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ "$glob_ddr05" != "${glob_ddr05/ddr/}" ]; then
         echo "#DDR_GROUP 6TH  WDB, WBD, CBQ Reject, retry, Flushing" >> $3
         ddr_events=" -e $glob_ddr05/config=127/,$glob_ddr05/config=20/,$glob_ddr05/config=21/,$glob_ddr05/config=22/,$glob_ddr05/config=23/,$glob_ddr05/config=24/,$glob_ddr05/config=25/,$glob_ddr05/config=26/,$glob_ddr05/config=27/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X62/$glob_ddr05:020 " $cp_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X62 DDR_0_6TH:020" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10647/$4 -e $glob_cpu_base/config=0x10646/$4 -e $glob_cpu_base/config=0x10645/$4 -e $glob_cpu_base/config=0x10644/$4 -e $glob_cpu_base/config=0x10643/$4 -e $glob_cpu_base/config=0x10642/$4 -e $glob_cpu_base/config=0x10641/$4 -e $glob_cpu_base/config=0x10640/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ "$glob_ddr05" != "${glob_ddr05/ddr/}" ]; then
         ddr_events=" -e $glob_ddr05/config=127/,$glob_ddr05/config=28/,$glob_ddr05/config=29/,$glob_ddr05/config=30/,$glob_ddr05/config=31/,$glob_ddr05/config=33/,$glob_ddr05/config=36/,$glob_ddr05/config=37/,$glob_ddr05/config=38/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X64/$glob_ddr05:028 " $cp_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X64 DDR_0_6TH:028" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x10656/$4 -e $glob_cpu_base/config=0x10655/$4 -e $glob_cpu_base/config=0x10654/$4 -e $glob_cpu_base/config=0x10653/$4 -e $glob_cpu_base/config=0x10652/$4 -e $glob_cpu_base/config=0x10651/$4 -e $glob_cpu_base/config=0x10650/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ "$glob_ddr05" != "${glob_ddr05/ddr/}" ]; then
         echo "#DDR_GROUP 6TH  CBQ BCQ, Ces, RDB" >> $3
         ddr_events=" -e $glob_ddr05/config=127/,$glob_ddr05/config=39/,$glob_ddr05/config=40/,$glob_ddr05/config=41/,$glob_ddr05/config=42/,$glob_ddr05/config=50/,$glob_ddr05/config=56/,$glob_ddr05/config=58/,$glob_ddr05/config=60/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X65/$glob_ddr05:039 " $cp_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X65 DDR_0_6TH:039" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP Branch Prediction (Target)" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10667/$4 -e $glob_cpu_base/config=0x10666/$4 -e $glob_cpu_base/config=0x10665/$4 -e $glob_cpu_base/config=0x10664/$4 -e $glob_cpu_base/config=0x10663/$4 -e $glob_cpu_base/config=0x10662/$4 -e $glob_cpu_base/config=0x10661/$4 -e $glob_cpu_base/config=0x10660/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ "$glob_ddr05" != "${glob_ddr05/ddr/}" ]; then
         echo "#DDR_GROUP 6TH  DBE BCQx is full" >> $3
         ddr_events=" -e $glob_ddr05/config=127/,$glob_ddr05/config=68/,$glob_ddr05/config=69/,$glob_ddr05/config=70/,$glob_ddr05/config=71/,$glob_ddr05/config=72/,$glob_ddr05/config=73/,$glob_ddr05/config=74/,$glob_ddr05/config=75/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X66/$glob_ddr05:068 " $cp_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X66 DDR_0_6TH:068" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x10677/$4 -e $glob_cpu_base/config=0x10676/$4 -e $glob_cpu_base/config=0x10675/$4 -e $glob_cpu_base/config=0x10674/$4 -e $glob_cpu_base/config=0x10673/$4 -e $glob_cpu_base/config=0x10672/$4 -e $glob_cpu_base/config=0x10671/$4 -e $glob_cpu_base/config=0x10670/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ "$glob_ddr05" != "${glob_ddr05/ddr/}" ]; then
         echo "#DDR_GROUP 6TH  Read/Write/Idle Cycles" >> $3
         ddr_events=" -e $glob_ddr05/config=127/,$glob_ddr05/config=94/,$glob_ddr05/config=98/,$glob_ddr05/config=99/,$glob_ddr05/config=100/,$glob_ddr05/config=60/,$glob_ddr05/config=61/,$glob_ddr05/config=62/,$glob_ddr05/config=63/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X67/$glob_ddr05:094 " $cp_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X67 DDR_0_6TH:094" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP Branch Prediction BTIC" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x106A7/$4 -e $glob_cpu_base/config=0x106A6/$4 -e $glob_cpu_base/config=0x106A5/$4 -e $glob_cpu_base/config=0x106A4/$4 -e $glob_cpu_base/config=0x106A3/$4 -e $glob_cpu_base/config=0x106A2/$4 -e $glob_cpu_base/config=0x106A1/$4 -e $glob_cpu_base/config=0x106A0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ "$glob_ddr05" != "${glob_ddr05/ddr/}" ]; then
         echo "#DDR_GROUP 6TH  DBE OPT x Full" >> $3
         ddr_events=" -e $glob_ddr05/config=127/,$glob_ddr05/config=101/,$glob_ddr05/config=102/,$glob_ddr05/config=103/,$glob_ddr05/config=104/,$glob_ddr05/config=106/,$glob_ddr05/config=107/,$glob_ddr05/config=108/,$glob_ddr05/config=109/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X6A/$glob_ddr05:101 " $cp_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X6A DDR_0_6TH:101" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x106B7/$4 -e $glob_cpu_base/config=0x106B6/$4 -e $glob_cpu_base/config=0x106B5/$4 -e $glob_cpu_base/config=0x106B4/$4 -e $glob_cpu_base/config=0x106B3/$4 -e $glob_cpu_base/config=0x106B2/$4 -e $glob_cpu_base/config=0x106B1/$4 -e $glob_cpu_base/config=0x106B0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi
      if [ "$glob_ddr05" != "${glob_ddr05/ddr/}" ]; then
         echo "#DDR_GROUP 6TH  Thermal, Refresh, Powerdown Info" >> $3
         ddr_events=" -e $glob_ddr05/config=127/,$glob_ddr05/config=109/,$glob_ddr05/config=110/,$glob_ddr05/config=146/,$glob_ddr05/config=147/,$glob_ddr05/config=148/,$glob_ddr05/config=149/,$glob_ddr05/config=150/,$glob_ddr05/config=152/ "
         perf_needed=1
      else
         ddr_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X6B/$glob_ddr05:109 " $cp_events $ddr_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X6B DDR_0_6TH:109" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x106C7/$4 -e $glob_cpu_base/config=0x106C6/$4 -e $glob_cpu_base/config=0x106C5/$4 -e $glob_cpu_base/config=0x106C4/$4 -e $glob_cpu_base/config=0x106C3/$4 -e $glob_cpu_base/config=0x106C2/$4 -e $glob_cpu_base/config=0x106C1/$4 -e $glob_cpu_base/config=0x106C0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X6C " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X6C" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x106D6/$4 -e $glob_cpu_base/config=0x106D5/$4 -e $glob_cpu_base/config=0x106D4/$4 -e $glob_cpu_base/config=0x106D3/$4 -e $glob_cpu_base/config=0x106D2/$4 -e $glob_cpu_base/config=0x106D1/$4 -e $glob_cpu_base/config=0x106D0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X6D " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X6D" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP Debug" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x10706/$4 -e $glob_cpu_base/config=0x10705/$4 -e $glob_cpu_base/config=0x10704/$4 -e $glob_cpu_base/config=0x10703/$4 -e $glob_cpu_base/config=0x10702/$4 -e $glob_cpu_base/config=0x10701/$4 -e $glob_cpu_base/config=0x10700/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR0:0X70 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR0:0X70" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP Placeholder" >> $3
         echo "#GROUP XU Constants" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x11007/$4 -e $glob_cpu_base/config=0x11006/$4 -e $glob_cpu_base/config=0x11005/$4 -e $glob_cpu_base/config=0x11004/$4 -e $glob_cpu_base/config=0x11003/$4 -e $glob_cpu_base/config=0x11002/$4 -e $glob_cpu_base/config=0x11001/$4 -e $glob_cpu_base/config=0x11000/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X00 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X00" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP XU Expand Events" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x11087/$4 -e $glob_cpu_base/config=0x11086/$4 -e $glob_cpu_base/config=0x11085/$4 -e $glob_cpu_base/config=0x11084/$4 -e $glob_cpu_base/config=0x11083/$4 -e $glob_cpu_base/config=0x11082/$4 -e $glob_cpu_base/config=0x11081/$4 -e $glob_cpu_base/config=0x11080/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X08 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X08" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x11096/$4 -e $glob_cpu_base/config=0x11095/$4 -e $glob_cpu_base/config=0x11094/$4 -e $glob_cpu_base/config=0x11093/$4 -e $glob_cpu_base/config=0x11092/$4 -e $glob_cpu_base/config=0x11091/$4 -e $glob_cpu_base/config=0x11090/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X09 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X09" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x110A7/$4 -e $glob_cpu_base/config=0x110A6/$4 -e $glob_cpu_base/config=0x110A5/$4 -e $glob_cpu_base/config=0x110A4/$4 -e $glob_cpu_base/config=0x110A3/$4 -e $glob_cpu_base/config=0x110A2/$4 -e $glob_cpu_base/config=0x110A1/$4 -e $glob_cpu_base/config=0x110A0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X0A " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X0A" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x110B7/$4 -e $glob_cpu_base/config=0x110B6/$4 -e $glob_cpu_base/config=0x110B5/$4 -e $glob_cpu_base/config=0x110B4/$4 -e $glob_cpu_base/config=0x110B3/$4 -e $glob_cpu_base/config=0x110B2/$4 -e $glob_cpu_base/config=0x110B1/$4 -e $glob_cpu_base/config=0x110B0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X0B " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X0B" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x110C6/$4 -e $glob_cpu_base/config=0x110C5/$4 -e $glob_cpu_base/config=0x110C4/$4 -e $glob_cpu_base/config=0x110C3/$4 -e $glob_cpu_base/config=0x110C2/$4 -e $glob_cpu_base/config=0x110C1/$4 -e $glob_cpu_base/config=0x110C0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X0C " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X0C" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x110D6/$4 -e $glob_cpu_base/config=0x110D5/$4 -e $glob_cpu_base/config=0x110D4/$4 -e $glob_cpu_base/config=0x110D3/$4 -e $glob_cpu_base/config=0x110D2/$4 -e $glob_cpu_base/config=0x110D1/$4 -e $glob_cpu_base/config=0x110D0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X0D " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X0D" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP XU Rename Events" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x11107/$4 -e $glob_cpu_base/config=0x11106/$4 -e $glob_cpu_base/config=0x11105/$4 -e $glob_cpu_base/config=0x11104/$4 -e $glob_cpu_base/config=0x11103/$4 -e $glob_cpu_base/config=0x11102/$4 -e $glob_cpu_base/config=0x11101/$4 -e $glob_cpu_base/config=0x11100/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X10 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X10" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP XU RACC Events" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x11186/$4 -e $glob_cpu_base/config=0x11185/$4 -e $glob_cpu_base/config=0x11184/$4 -e $glob_cpu_base/config=0x11183/$4 -e $glob_cpu_base/config=0x11182/$4 -e $glob_cpu_base/config=0x11181/$4 -e $glob_cpu_base/config=0x11180/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X18 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X18" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x11196/$4 -e $glob_cpu_base/config=0x11195/$4 -e $glob_cpu_base/config=0x11194/$4 -e $glob_cpu_base/config=0x11193/$4 -e $glob_cpu_base/config=0x11192/$4 -e $glob_cpu_base/config=0x11191/$4 -e $glob_cpu_base/config=0x11190/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X19 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X19" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x111A7/$4 -e $glob_cpu_base/config=0x111A6/$4 -e $glob_cpu_base/config=0x111A5/$4 -e $glob_cpu_base/config=0x111A4/$4 -e $glob_cpu_base/config=0x111A3/$4 -e $glob_cpu_base/config=0x111A2/$4 -e $glob_cpu_base/config=0x111A1/$4 -e $glob_cpu_base/config=0x111A0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X1A " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X1A" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x111B7/$4 -e $glob_cpu_base/config=0x111B6/$4 -e $glob_cpu_base/config=0x111B5/$4 -e $glob_cpu_base/config=0x111B4/$4 -e $glob_cpu_base/config=0x111B3/$4 -e $glob_cpu_base/config=0x111B2/$4 -e $glob_cpu_base/config=0x111B1/$4 -e $glob_cpu_base/config=0x111B0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X1B " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X1B" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x111C7/$4 -e $glob_cpu_base/config=0x111C6/$4 -e $glob_cpu_base/config=0x111C5/$4 -e $glob_cpu_base/config=0x111C4/$4 -e $glob_cpu_base/config=0x111C3/$4 -e $glob_cpu_base/config=0x111C2/$4 -e $glob_cpu_base/config=0x111C1/$4 -e $glob_cpu_base/config=0x111C0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X1C " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X1C" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x111D7/$4 -e $glob_cpu_base/config=0x111D6/$4 -e $glob_cpu_base/config=0x111D5/$4 -e $glob_cpu_base/config=0x111D4/$4 -e $glob_cpu_base/config=0x111D3/$4 -e $glob_cpu_base/config=0x111D2/$4 -e $glob_cpu_base/config=0x111D1/$4 -e $glob_cpu_base/config=0x111D0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X1D " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X1D" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x111E7/$4 -e $glob_cpu_base/config=0x111E6/$4 -e $glob_cpu_base/config=0x111E5/$4 -e $glob_cpu_base/config=0x111E4/$4 -e $glob_cpu_base/config=0x111E3/$4 -e $glob_cpu_base/config=0x111E2/$4 -e $glob_cpu_base/config=0x111E1/$4 -e $glob_cpu_base/config=0x111E0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X1E " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X1E" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x111F7/$4 -e $glob_cpu_base/config=0x111F6/$4 -e $glob_cpu_base/config=0x111F5/$4 -e $glob_cpu_base/config=0x111F4/$4 -e $glob_cpu_base/config=0x111F3/$4 -e $glob_cpu_base/config=0x111F2/$4 -e $glob_cpu_base/config=0x111F1/$4 -e $glob_cpu_base/config=0x111F0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X1F " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X1F" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x11207/$4 -e $glob_cpu_base/config=0x11206/$4 -e $glob_cpu_base/config=0x11205/$4 -e $glob_cpu_base/config=0x11204/$4 -e $glob_cpu_base/config=0x11203/$4 -e $glob_cpu_base/config=0x11202/$4 -e $glob_cpu_base/config=0x11201/$4 -e $glob_cpu_base/config=0x11200/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X20 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X20" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x11216/$4 -e $glob_cpu_base/config=0x11215/$4 -e $glob_cpu_base/config=0x11214/$4 -e $glob_cpu_base/config=0x11213/$4 -e $glob_cpu_base/config=0x11212/$4 -e $glob_cpu_base/config=0x11211/$4 -e $glob_cpu_base/config=0x11210/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X21 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X21" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP XU Book Events" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x11287/$4 -e $glob_cpu_base/config=0x11286/$4 -e $glob_cpu_base/config=0x11285/$4 -e $glob_cpu_base/config=0x11284/$4 -e $glob_cpu_base/config=0x11283/$4 -e $glob_cpu_base/config=0x11282/$4 -e $glob_cpu_base/config=0x11281/$4 -e $glob_cpu_base/config=0x11280/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X28 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X28" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x11297/$4 -e $glob_cpu_base/config=0x11296/$4 -e $glob_cpu_base/config=0x11295/$4 -e $glob_cpu_base/config=0x11294/$4 -e $glob_cpu_base/config=0x11293/$4 -e $glob_cpu_base/config=0x11292/$4 -e $glob_cpu_base/config=0x11291/$4 -e $glob_cpu_base/config=0x11290/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X29 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X29" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP XU Dispatch Events" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x11307/$4 -e $glob_cpu_base/config=0x11306/$4 -e $glob_cpu_base/config=0x11305/$4 -e $glob_cpu_base/config=0x11304/$4 -e $glob_cpu_base/config=0x11303/$4 -e $glob_cpu_base/config=0x11302/$4 -e $glob_cpu_base/config=0x11301/$4 -e $glob_cpu_base/config=0x11300/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X30 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X30" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x11316/$4 -e $glob_cpu_base/config=0x11315/$4 -e $glob_cpu_base/config=0x11314/$4 -e $glob_cpu_base/config=0x11313/$4 -e $glob_cpu_base/config=0x11312/$4 -e $glob_cpu_base/config=0x11311/$4 -e $glob_cpu_base/config=0x11310/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X31 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X31" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x11327/$4 -e $glob_cpu_base/config=0x11326/$4 -e $glob_cpu_base/config=0x11325/$4 -e $glob_cpu_base/config=0x11324/$4 -e $glob_cpu_base/config=0x11323/$4 -e $glob_cpu_base/config=0x11322/$4 -e $glob_cpu_base/config=0x11321/$4 -e $glob_cpu_base/config=0x11320/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X32 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X32" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x11336/$4 -e $glob_cpu_base/config=0x11335/$4 -e $glob_cpu_base/config=0x11334/$4 -e $glob_cpu_base/config=0x11333/$4 -e $glob_cpu_base/config=0x11332/$4 -e $glob_cpu_base/config=0x11331/$4 -e $glob_cpu_base/config=0x11330/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X33 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X33" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x11347/$4 -e $glob_cpu_base/config=0x11346/$4 -e $glob_cpu_base/config=0x11345/$4 -e $glob_cpu_base/config=0x11344/$4 -e $glob_cpu_base/config=0x11343/$4 -e $glob_cpu_base/config=0x11342/$4 -e $glob_cpu_base/config=0x11341/$4 -e $glob_cpu_base/config=0x11340/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X34 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X34" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x11367/$4 -e $glob_cpu_base/config=0x11366/$4 -e $glob_cpu_base/config=0x11365/$4 -e $glob_cpu_base/config=0x11364/$4 -e $glob_cpu_base/config=0x11363/$4 -e $glob_cpu_base/config=0x11362/$4 -e $glob_cpu_base/config=0x11361/$4 -e $glob_cpu_base/config=0x11360/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X36 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X36" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x11377/$4 -e $glob_cpu_base/config=0x11376/$4 -e $glob_cpu_base/config=0x11375/$4 -e $glob_cpu_base/config=0x11374/$4 -e $glob_cpu_base/config=0x11373/$4 -e $glob_cpu_base/config=0x11372/$4 -e $glob_cpu_base/config=0x11371/$4 -e $glob_cpu_base/config=0x11370/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X37 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X37" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP XU Pipe Events" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x11407/$4 -e $glob_cpu_base/config=0x11406/$4 -e $glob_cpu_base/config=0x11405/$4 -e $glob_cpu_base/config=0x11404/$4 -e $glob_cpu_base/config=0x11403/$4 -e $glob_cpu_base/config=0x11402/$4 -e $glob_cpu_base/config=0x11401/$4 -e $glob_cpu_base/config=0x11400/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X40 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X40" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x11417/$4 -e $glob_cpu_base/config=0x11416/$4 -e $glob_cpu_base/config=0x11415/$4 -e $glob_cpu_base/config=0x11414/$4 -e $glob_cpu_base/config=0x11413/$4 -e $glob_cpu_base/config=0x11412/$4 -e $glob_cpu_base/config=0x11411/$4 -e $glob_cpu_base/config=0x11410/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X41 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X41" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x11427/$4 -e $glob_cpu_base/config=0x11426/$4 -e $glob_cpu_base/config=0x11425/$4 -e $glob_cpu_base/config=0x11424/$4 -e $glob_cpu_base/config=0x11423/$4 -e $glob_cpu_base/config=0x11422/$4 -e $glob_cpu_base/config=0x11421/$4 -e $glob_cpu_base/config=0x11420/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X42 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X42" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x11437/$4 -e $glob_cpu_base/config=0x11436/$4 -e $glob_cpu_base/config=0x11435/$4 -e $glob_cpu_base/config=0x11434/$4 -e $glob_cpu_base/config=0x11433/$4 -e $glob_cpu_base/config=0x11432/$4 -e $glob_cpu_base/config=0x11431/$4 -e $glob_cpu_base/config=0x11430/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X43 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X43" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x11447/$4 -e $glob_cpu_base/config=0x11446/$4 -e $glob_cpu_base/config=0x11445/$4 -e $glob_cpu_base/config=0x11444/$4 -e $glob_cpu_base/config=0x11443/$4 -e $glob_cpu_base/config=0x11442/$4 -e $glob_cpu_base/config=0x11441/$4 -e $glob_cpu_base/config=0x11440/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X44 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X44" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP XU CFP Events" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x11507/$4 -e $glob_cpu_base/config=0x11506/$4 -e $glob_cpu_base/config=0x11505/$4 -e $glob_cpu_base/config=0x11504/$4 -e $glob_cpu_base/config=0x11503/$4 -e $glob_cpu_base/config=0x11502/$4 -e $glob_cpu_base/config=0x11501/$4 -e $glob_cpu_base/config=0x11500/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X50 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X50" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP XU Matrix Events" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x11586/$4 -e $glob_cpu_base/config=0x11585/$4 -e $glob_cpu_base/config=0x11584/$4 -e $glob_cpu_base/config=0x11583/$4 -e $glob_cpu_base/config=0x11582/$4 -e $glob_cpu_base/config=0x11581/$4 -e $glob_cpu_base/config=0x11580/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X58 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X58" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP XU Flush Recovery Events" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x11607/$4 -e $glob_cpu_base/config=0x11606/$4 -e $glob_cpu_base/config=0x11605/$4 -e $glob_cpu_base/config=0x11604/$4 -e $glob_cpu_base/config=0x11603/$4 -e $glob_cpu_base/config=0x11602/$4 -e $glob_cpu_base/config=0x11601/$4 -e $glob_cpu_base/config=0x11600/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X60 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X60" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x11616/$4 -e $glob_cpu_base/config=0x11615/$4 -e $glob_cpu_base/config=0x11614/$4 -e $glob_cpu_base/config=0x11613/$4 -e $glob_cpu_base/config=0x11612/$4 -e $glob_cpu_base/config=0x11611/$4 -e $glob_cpu_base/config=0x11610/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X61 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X61" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP XU MISC Events" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x11786/$4 -e $glob_cpu_base/config=0x11785/$4 -e $glob_cpu_base/config=0x11784/$4 -e $glob_cpu_base/config=0x11783/$4 -e $glob_cpu_base/config=0x11782/$4 -e $glob_cpu_base/config=0x11781/$4 -e $glob_cpu_base/config=0x11780/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR1:0X78 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR1:0X78" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP SU Constants" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12007/$4 -e $glob_cpu_base/config=0x12006/$4 -e $glob_cpu_base/config=0x12005/$4 -e $glob_cpu_base/config=0x12004/$4 -e $glob_cpu_base/config=0x12003/$4 -e $glob_cpu_base/config=0x12002/$4 -e $glob_cpu_base/config=0x12001/$4 -e $glob_cpu_base/config=0x12000/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X00 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X00" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP SU Types of requests in LS Pipelines" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12017/$4 -e $glob_cpu_base/config=0x12016/$4 -e $glob_cpu_base/config=0x12015/$4 -e $glob_cpu_base/config=0x12014/$4 -e $glob_cpu_base/config=0x12013/$4 -e $glob_cpu_base/config=0x12012/$4 -e $glob_cpu_base/config=0x12011/$4 -e $glob_cpu_base/config=0x12010/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X01 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X01" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12027/$4 -e $glob_cpu_base/config=0x12026/$4 -e $glob_cpu_base/config=0x12025/$4 -e $glob_cpu_base/config=0x12024/$4 -e $glob_cpu_base/config=0x12023/$4 -e $glob_cpu_base/config=0x12022/$4 -e $glob_cpu_base/config=0x12021/$4 -e $glob_cpu_base/config=0x12020/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X02 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X02" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12037/$4 -e $glob_cpu_base/config=0x12036/$4 -e $glob_cpu_base/config=0x12035/$4 -e $glob_cpu_base/config=0x12034/$4 -e $glob_cpu_base/config=0x12033/$4 -e $glob_cpu_base/config=0x12032/$4 -e $glob_cpu_base/config=0x12031/$4 -e $glob_cpu_base/config=0x12030/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X03 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X03" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP SU L1 Data Cache virtual tag (L1DCVTAG)" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x12046/$4 -e $glob_cpu_base/config=0x12045/$4 -e $glob_cpu_base/config=0x12044/$4 -e $glob_cpu_base/config=0x12043/$4 -e $glob_cpu_base/config=0x12042/$4 -e $glob_cpu_base/config=0x12041/$4 -e $glob_cpu_base/config=0x12040/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X04 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X04" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x12056/$4 -e $glob_cpu_base/config=0x12055/$4 -e $glob_cpu_base/config=0x12054/$4 -e $glob_cpu_base/config=0x12053/$4 -e $glob_cpu_base/config=0x12052/$4 -e $glob_cpu_base/config=0x12051/$4 -e $glob_cpu_base/config=0x12050/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X05 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X05" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP SU LS Pipelines" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12067/$4 -e $glob_cpu_base/config=0x12066/$4 -e $glob_cpu_base/config=0x12065/$4 -e $glob_cpu_base/config=0x12064/$4 -e $glob_cpu_base/config=0x12063/$4 -e $glob_cpu_base/config=0x12062/$4 -e $glob_cpu_base/config=0x12061/$4 -e $glob_cpu_base/config=0x12060/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X06 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X06" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12077/$4 -e $glob_cpu_base/config=0x12076/$4 -e $glob_cpu_base/config=0x12075/$4 -e $glob_cpu_base/config=0x12074/$4 -e $glob_cpu_base/config=0x12073/$4 -e $glob_cpu_base/config=0x12072/$4 -e $glob_cpu_base/config=0x12071/$4 -e $glob_cpu_base/config=0x12070/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X07 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X07" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12087/$4 -e $glob_cpu_base/config=0x12086/$4 -e $glob_cpu_base/config=0x12085/$4 -e $glob_cpu_base/config=0x12084/$4 -e $glob_cpu_base/config=0x12083/$4 -e $glob_cpu_base/config=0x12082/$4 -e $glob_cpu_base/config=0x12081/$4 -e $glob_cpu_base/config=0x12080/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X08 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X08" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12097/$4 -e $glob_cpu_base/config=0x12096/$4 -e $glob_cpu_base/config=0x12095/$4 -e $glob_cpu_base/config=0x12094/$4 -e $glob_cpu_base/config=0x12093/$4 -e $glob_cpu_base/config=0x12092/$4 -e $glob_cpu_base/config=0x12091/$4 -e $glob_cpu_base/config=0x12090/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X09 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X09" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x120a7/$4 -e $glob_cpu_base/config=0x120a6/$4 -e $glob_cpu_base/config=0x120a5/$4 -e $glob_cpu_base/config=0x120a4/$4 -e $glob_cpu_base/config=0x120a3/$4 -e $glob_cpu_base/config=0x120a2/$4 -e $glob_cpu_base/config=0x120a1/$4 -e $glob_cpu_base/config=0x120a0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X0A " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X0A" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP SU Pipeline Load Data Return" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x120b7/$4 -e $glob_cpu_base/config=0x120b6/$4 -e $glob_cpu_base/config=0x120b5/$4 -e $glob_cpu_base/config=0x120b4/$4 -e $glob_cpu_base/config=0x120b3/$4 -e $glob_cpu_base/config=0x120b2/$4 -e $glob_cpu_base/config=0x120b1/$4 -e $glob_cpu_base/config=0x120b0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X0B " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X0B" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x120c6/$4 -e $glob_cpu_base/config=0x120c5/$4 -e $glob_cpu_base/config=0x120c4/$4 -e $glob_cpu_base/config=0x120c3/$4 -e $glob_cpu_base/config=0x120c2/$4 -e $glob_cpu_base/config=0x120c1/$4 -e $glob_cpu_base/config=0x120c0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X0C " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X0C" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP SU DTLB" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x120d7/$4 -e $glob_cpu_base/config=0x120d6/$4 -e $glob_cpu_base/config=0x120d5/$4 -e $glob_cpu_base/config=0x120d4/$4 -e $glob_cpu_base/config=0x120d3/$4 -e $glob_cpu_base/config=0x120d2/$4 -e $glob_cpu_base/config=0x120d1/$4 -e $glob_cpu_base/config=0x120d0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X0D " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X0D" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x120e6/$4 -e $glob_cpu_base/config=0x120e5/$4 -e $glob_cpu_base/config=0x120e4/$4 -e $glob_cpu_base/config=0x120e3/$4 -e $glob_cpu_base/config=0x120e2/$4 -e $glob_cpu_base/config=0x120e1/$4 -e $glob_cpu_base/config=0x120e0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X0E " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X0E" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP SU STQ" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12187/$4 -e $glob_cpu_base/config=0x12186/$4 -e $glob_cpu_base/config=0x12185/$4 -e $glob_cpu_base/config=0x12184/$4 -e $glob_cpu_base/config=0x12183/$4 -e $glob_cpu_base/config=0x12182/$4 -e $glob_cpu_base/config=0x12181/$4 -e $glob_cpu_base/config=0x12180/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X18 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X18" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x12196/$4 -e $glob_cpu_base/config=0x12195/$4 -e $glob_cpu_base/config=0x12194/$4 -e $glob_cpu_base/config=0x12193/$4 -e $glob_cpu_base/config=0x12192/$4 -e $glob_cpu_base/config=0x12191/$4 -e $glob_cpu_base/config=0x12190/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X19 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X19" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP SU Punt Flush Requests" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x121c7/$4 -e $glob_cpu_base/config=0x121c6/$4 -e $glob_cpu_base/config=0x121c5/$4 -e $glob_cpu_base/config=0x121c4/$4 -e $glob_cpu_base/config=0x121c3/$4 -e $glob_cpu_base/config=0x121c2/$4 -e $glob_cpu_base/config=0x121c1/$4 -e $glob_cpu_base/config=0x121c0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X1C " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X1C" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x121d7/$4 -e $glob_cpu_base/config=0x121d6/$4 -e $glob_cpu_base/config=0x121d5/$4 -e $glob_cpu_base/config=0x121d4/$4 -e $glob_cpu_base/config=0x121d3/$4 -e $glob_cpu_base/config=0x121d2/$4 -e $glob_cpu_base/config=0x121d1/$4 -e $glob_cpu_base/config=0x121d0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X1D " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X1D" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x121f7/$4 -e $glob_cpu_base/config=0x121f6/$4 -e $glob_cpu_base/config=0x121f5/$4 -e $glob_cpu_base/config=0x121f4/$4 -e $glob_cpu_base/config=0x121f3/$4 -e $glob_cpu_base/config=0x121f2/$4 -e $glob_cpu_base/config=0x121f1/$4 -e $glob_cpu_base/config=0x121f0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X1F " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X1F" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x12406/$4 -e $glob_cpu_base/config=0x12405/$4 -e $glob_cpu_base/config=0x12404/$4 -e $glob_cpu_base/config=0x12403/$4 -e $glob_cpu_base/config=0x12402/$4 -e $glob_cpu_base/config=0x12401/$4 -e $glob_cpu_base/config=0x12400/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X40 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X40" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP SU Blank" >> $3
         echo "#GROUP SU L1 Data Cache physical tag pipeline movement" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12417/$4 -e $glob_cpu_base/config=0x12416/$4 -e $glob_cpu_base/config=0x12415/$4 -e $glob_cpu_base/config=0x12414/$4 -e $glob_cpu_base/config=0x12413/$4 -e $glob_cpu_base/config=0x12412/$4 -e $glob_cpu_base/config=0x12411/$4 -e $glob_cpu_base/config=0x12410/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X41 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X41" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP SU UTLB" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12427/$4 -e $glob_cpu_base/config=0x12426/$4 -e $glob_cpu_base/config=0x12425/$4 -e $glob_cpu_base/config=0x12424/$4 -e $glob_cpu_base/config=0x12423/$4 -e $glob_cpu_base/config=0x12422/$4 -e $glob_cpu_base/config=0x12421/$4 -e $glob_cpu_base/config=0x12420/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X42 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X42" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP SU S1FTLB/$INFTLB" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12437/$4 -e $glob_cpu_base/config=0x12436/$4 -e $glob_cpu_base/config=0x12435/$4 -e $glob_cpu_base/config=0x12434/$4 -e $glob_cpu_base/config=0x12433/$4 -e $glob_cpu_base/config=0x12432/$4 -e $glob_cpu_base/config=0x12431/$4 -e $glob_cpu_base/config=0x12430/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X43 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X43" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12447/$4 -e $glob_cpu_base/config=0x12446/$4 -e $glob_cpu_base/config=0x12445/$4 -e $glob_cpu_base/config=0x12444/$4 -e $glob_cpu_base/config=0x12443/$4 -e $glob_cpu_base/config=0x12442/$4 -e $glob_cpu_base/config=0x12441/$4 -e $glob_cpu_base/config=0x12440/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X44 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X44" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12457/$4 -e $glob_cpu_base/config=0x12456/$4 -e $glob_cpu_base/config=0x12455/$4 -e $glob_cpu_base/config=0x12454/$4 -e $glob_cpu_base/config=0x12453/$4 -e $glob_cpu_base/config=0x12452/$4 -e $glob_cpu_base/config=0x12451/$4 -e $glob_cpu_base/config=0x12450/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X45 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X45" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12467/$4 -e $glob_cpu_base/config=0x12466/$4 -e $glob_cpu_base/config=0x12465/$4 -e $glob_cpu_base/config=0x12464/$4 -e $glob_cpu_base/config=0x12463/$4 -e $glob_cpu_base/config=0x12462/$4 -e $glob_cpu_base/config=0x12461/$4 -e $glob_cpu_base/config=0x12460/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X46 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X46" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x12476/$4 -e $glob_cpu_base/config=0x12475/$4 -e $glob_cpu_base/config=0x12474/$4 -e $glob_cpu_base/config=0x12473/$4 -e $glob_cpu_base/config=0x12472/$4 -e $glob_cpu_base/config=0x12471/$4 -e $glob_cpu_base/config=0x12470/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X47 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X47" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP SU S2TLB" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12487/$4 -e $glob_cpu_base/config=0x12486/$4 -e $glob_cpu_base/config=0x12485/$4 -e $glob_cpu_base/config=0x12484/$4 -e $glob_cpu_base/config=0x12483/$4 -e $glob_cpu_base/config=0x12482/$4 -e $glob_cpu_base/config=0x12481/$4 -e $glob_cpu_base/config=0x12480/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X48 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X48" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12497/$4 -e $glob_cpu_base/config=0x12496/$4 -e $glob_cpu_base/config=0x12495/$4 -e $glob_cpu_base/config=0x12494/$4 -e $glob_cpu_base/config=0x12493/$4 -e $glob_cpu_base/config=0x12492/$4 -e $glob_cpu_base/config=0x12491/$4 -e $glob_cpu_base/config=0x12490/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X49 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X49" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x124a7/$4 -e $glob_cpu_base/config=0x124a6/$4 -e $glob_cpu_base/config=0x124a5/$4 -e $glob_cpu_base/config=0x124a4/$4 -e $glob_cpu_base/config=0x124a3/$4 -e $glob_cpu_base/config=0x124a2/$4 -e $glob_cpu_base/config=0x124a1/$4 -e $glob_cpu_base/config=0x124a0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X4A " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X4A" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x124b7/$4 -e $glob_cpu_base/config=0x124b6/$4 -e $glob_cpu_base/config=0x124b5/$4 -e $glob_cpu_base/config=0x124b4/$4 -e $glob_cpu_base/config=0x124b3/$4 -e $glob_cpu_base/config=0x124b2/$4 -e $glob_cpu_base/config=0x124b1/$4 -e $glob_cpu_base/config=0x124b0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X4B " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X4B" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x124c6/$4 -e $glob_cpu_base/config=0x124c5/$4 -e $glob_cpu_base/config=0x124c4/$4 -e $glob_cpu_base/config=0x124c3/$4 -e $glob_cpu_base/config=0x124c2/$4 -e $glob_cpu_base/config=0x124c1/$4 -e $glob_cpu_base/config=0x124c0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X4C " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X4C" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP SU MMU Movement" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x124d7/$4 -e $glob_cpu_base/config=0x124d6/$4 -e $glob_cpu_base/config=0x124d5/$4 -e $glob_cpu_base/config=0x124d4/$4 -e $glob_cpu_base/config=0x124d3/$4 -e $glob_cpu_base/config=0x124d2/$4 -e $glob_cpu_base/config=0x124d1/$4 -e $glob_cpu_base/config=0x124d0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X4D " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X4D" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x124e7/$4 -e $glob_cpu_base/config=0x124e6/$4 -e $glob_cpu_base/config=0x124e5/$4 -e $glob_cpu_base/config=0x124e4/$4 -e $glob_cpu_base/config=0x124e3/$4 -e $glob_cpu_base/config=0x124e2/$4 -e $glob_cpu_base/config=0x124e1/$4 -e $glob_cpu_base/config=0x124e0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X4E " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X4E" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x124f7/$4 -e $glob_cpu_base/config=0x124f6/$4 -e $glob_cpu_base/config=0x124f5/$4 -e $glob_cpu_base/config=0x124f4/$4 -e $glob_cpu_base/config=0x124f3/$4 -e $glob_cpu_base/config=0x124f2/$4 -e $glob_cpu_base/config=0x124f1/$4 -e $glob_cpu_base/config=0x124f0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X4F " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X4F" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x12506/$4 -e $glob_cpu_base/config=0x12505/$4 -e $glob_cpu_base/config=0x12504/$4 -e $glob_cpu_base/config=0x12503/$4 -e $glob_cpu_base/config=0x12502/$4 -e $glob_cpu_base/config=0x12501/$4 -e $glob_cpu_base/config=0x12500/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X50 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X50" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP SU Hardware Prefetch Engine" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x12516/$4 -e $glob_cpu_base/config=0x12515/$4 -e $glob_cpu_base/config=0x12514/$4 -e $glob_cpu_base/config=0x12513/$4 -e $glob_cpu_base/config=0x12512/$4 -e $glob_cpu_base/config=0x12511/$4 -e $glob_cpu_base/config=0x12510/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X51 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X51" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12527/$4 -e $glob_cpu_base/config=0x12526/$4 -e $glob_cpu_base/config=0x12525/$4 -e $glob_cpu_base/config=0x12524/$4 -e $glob_cpu_base/config=0x12523/$4 -e $glob_cpu_base/config=0x12522/$4 -e $glob_cpu_base/config=0x12521/$4 -e $glob_cpu_base/config=0x12520/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X52 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X52" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12537/$4 -e $glob_cpu_base/config=0x12536/$4 -e $glob_cpu_base/config=0x12535/$4 -e $glob_cpu_base/config=0x12534/$4 -e $glob_cpu_base/config=0x12533/$4 -e $glob_cpu_base/config=0x12532/$4 -e $glob_cpu_base/config=0x12531/$4 -e $glob_cpu_base/config=0x12530/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X53 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X53" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x12546/$4 -e $glob_cpu_base/config=0x12545/$4 -e $glob_cpu_base/config=0x12544/$4 -e $glob_cpu_base/config=0x12543/$4 -e $glob_cpu_base/config=0x12542/$4 -e $glob_cpu_base/config=0x12541/$4 -e $glob_cpu_base/config=0x12540/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X54 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X54" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12557/$4 -e $glob_cpu_base/config=0x12556/$4 -e $glob_cpu_base/config=0x12555/$4 -e $glob_cpu_base/config=0x12554/$4 -e $glob_cpu_base/config=0x12553/$4 -e $glob_cpu_base/config=0x12552/$4 -e $glob_cpu_base/config=0x12551/$4 -e $glob_cpu_base/config=0x12550/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X55 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X55" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12567/$4 -e $glob_cpu_base/config=0x12566/$4 -e $glob_cpu_base/config=0x12565/$4 -e $glob_cpu_base/config=0x12564/$4 -e $glob_cpu_base/config=0x12563/$4 -e $glob_cpu_base/config=0x12562/$4 -e $glob_cpu_base/config=0x12561/$4 -e $glob_cpu_base/config=0x12560/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X56 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X56" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12577/$4 -e $glob_cpu_base/config=0x12576/$4 -e $glob_cpu_base/config=0x12575/$4 -e $glob_cpu_base/config=0x12574/$4 -e $glob_cpu_base/config=0x12573/$4 -e $glob_cpu_base/config=0x12572/$4 -e $glob_cpu_base/config=0x12571/$4 -e $glob_cpu_base/config=0x12570/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X57 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X57" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x12586/$4 -e $glob_cpu_base/config=0x12585/$4 -e $glob_cpu_base/config=0x12584/$4 -e $glob_cpu_base/config=0x12583/$4 -e $glob_cpu_base/config=0x12582/$4 -e $glob_cpu_base/config=0x12581/$4 -e $glob_cpu_base/config=0x12580/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X58 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X58" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12597/$4 -e $glob_cpu_base/config=0x12596/$4 -e $glob_cpu_base/config=0x12595/$4 -e $glob_cpu_base/config=0x12594/$4 -e $glob_cpu_base/config=0x12593/$4 -e $glob_cpu_base/config=0x12592/$4 -e $glob_cpu_base/config=0x12591/$4 -e $glob_cpu_base/config=0x12590/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X59 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X59" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x125A7/$4 -e $glob_cpu_base/config=0x125A6/$4 -e $glob_cpu_base/config=0x125A5/$4 -e $glob_cpu_base/config=0x125A4/$4 -e $glob_cpu_base/config=0x125A3/$4 -e $glob_cpu_base/config=0x125A2/$4 -e $glob_cpu_base/config=0x125A1/$4 -e $glob_cpu_base/config=0x125A0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X5A " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X5A" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x125B7/$4 -e $glob_cpu_base/config=0x125B6/$4 -e $glob_cpu_base/config=0x125B5/$4 -e $glob_cpu_base/config=0x125B4/$4 -e $glob_cpu_base/config=0x125B3/$4 -e $glob_cpu_base/config=0x125B2/$4 -e $glob_cpu_base/config=0x125B1/$4 -e $glob_cpu_base/config=0x125B0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X5B " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X5B" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x125C7/$4 -e $glob_cpu_base/config=0x125C6/$4 -e $glob_cpu_base/config=0x125C5/$4 -e $glob_cpu_base/config=0x125C4/$4 -e $glob_cpu_base/config=0x125C3/$4 -e $glob_cpu_base/config=0x125C2/$4 -e $glob_cpu_base/config=0x125C1/$4 -e $glob_cpu_base/config=0x125C0/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X5C " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X5C" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP SU MEMQAW movement" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12607/$4 -e $glob_cpu_base/config=0x12606/$4 -e $glob_cpu_base/config=0x12605/$4 -e $glob_cpu_base/config=0x12604/$4 -e $glob_cpu_base/config=0x12603/$4 -e $glob_cpu_base/config=0x12602/$4 -e $glob_cpu_base/config=0x12601/$4 -e $glob_cpu_base/config=0x12600/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X60 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X60" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x12616/$4 -e $glob_cpu_base/config=0x12615/$4 -e $glob_cpu_base/config=0x12614/$4 -e $glob_cpu_base/config=0x12613/$4 -e $glob_cpu_base/config=0x12612/$4 -e $glob_cpu_base/config=0x12611/$4 -e $glob_cpu_base/config=0x12610/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X61 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X61" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x8/$4     -e $glob_cpu_base/config=0x12626/$4 -e $glob_cpu_base/config=0x12625/$4 -e $glob_cpu_base/config=0x12624/$4 -e $glob_cpu_base/config=0x12623/$4 -e $glob_cpu_base/config=0x12622/$4 -e $glob_cpu_base/config=0x12621/$4 -e $glob_cpu_base/config=0x12620/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X62 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X62" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP SU MEMQ utilization" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12707/$4 -e $glob_cpu_base/config=0x12706/$4 -e $glob_cpu_base/config=0x12705/$4 -e $glob_cpu_base/config=0x12704/$4 -e $glob_cpu_base/config=0x12703/$4 -e $glob_cpu_base/config=0x12702/$4 -e $glob_cpu_base/config=0x12701/$4 -e $glob_cpu_base/config=0x12700/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X70 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X70" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12717/$4 -e $glob_cpu_base/config=0x12716/$4 -e $glob_cpu_base/config=0x12715/$4 -e $glob_cpu_base/config=0x12714/$4 -e $glob_cpu_base/config=0x12713/$4 -e $glob_cpu_base/config=0x12712/$4 -e $glob_cpu_base/config=0x12711/$4 -e $glob_cpu_base/config=0x12710/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X71 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X71" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12727/$4 -e $glob_cpu_base/config=0x12726/$4 -e $glob_cpu_base/config=0x12725/$4 -e $glob_cpu_base/config=0x12724/$4 -e $glob_cpu_base/config=0x12723/$4 -e $glob_cpu_base/config=0x12722/$4 -e $glob_cpu_base/config=0x12721/$4 -e $glob_cpu_base/config=0x12720/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X72 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X72" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12787/$4 -e $glob_cpu_base/config=0x12786/$4 -e $glob_cpu_base/config=0x12785/$4 -e $glob_cpu_base/config=0x12784/$4 -e $glob_cpu_base/config=0x12783/$4 -e $glob_cpu_base/config=0x12782/$4 -e $glob_cpu_base/config=0x12781/$4 -e $glob_cpu_base/config=0x12780/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X78 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X78" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         echo "#GROUP SU Snooped I-Cache invalidates" >> $3
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12797/$4 -e $glob_cpu_base/config=0x12796/$4 -e $glob_cpu_base/config=0x12795/$4 -e $glob_cpu_base/config=0x12794/$4 -e $glob_cpu_base/config=0x12793/$4 -e $glob_cpu_base/config=0x12792/$4 -e $glob_cpu_base/config=0x12791/$4 -e $glob_cpu_base/config=0x12790/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X79 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X79" $3
   let "event_index++"

   if [ $1 -eq $event_index ]
   then
      if [ $glob_cpu -eq 1 ]; then
         cp_events=" -e cycles:$4 -e $glob_cpu_base/config=0x12807/$4 -e $glob_cpu_base/config=0x12806/$4 -e $glob_cpu_base/config=0x12805/$4 -e $glob_cpu_base/config=0x12804/$4 -e $glob_cpu_base/config=0x12803/$4 -e $glob_cpu_base/config=0x12802/$4 -e $glob_cpu_base/config=0x12801/$4 -e $glob_cpu_base/config=0x12800/$4 "
         perf_needed=1
      else
         cp_events=" "
      fi

      if [ $perf_needed -eq 1 ]; then
        perf stat --append --output=$3 -x  " PMRESR2:0X80 " $cp_events $2
      fi
      return $event_index
   fi
   print_index $1 "$event_index PMRESR2:0X80" $3
   let "event_index++"

  return $event_index
}

#MAIN Routine
#-------------------------------------------------------------------------------------------------------------------
# $1 a run count designation allowing the user to select a specific set of events to collect
#       5 would run the 5th set of events
#       "1 7 9 12" would run the 1st, 7th, 9th and 12the events
#       ALL will run them all
# $2 is the aplication name to run. could be something like:
#      "-C 6 taskset 0x40 app.elf args" (use quotes when necessary) - This will take care of single core execution with L2 properly isolated
#      "taskset 0x2 app.elf" - This will collect counts for where the application runs (cpu 1) but L2 counts will be sum of all L2s
#      "app.elf" - This will collect counts for wherever the application goes on a CPU and sum of all L2s
#      "-a app.elf" This will collect the sum across all CPus and all L2 
# $3 is the output file designation with 'append' optionally preceeding the name of the file 
# $4 Can be 'u' or 'k' to designate user or kernel mode collection. If $4 is blank, both user and kernel mode counts wll be collected
#------------------------------------------------------------------------------------------------------------------- 

append_flag=${3%% *}     # extract first word in the output file id string
output_id="${3#* }"  # extract all remaining words starting from the 2nd 

if [ "$append_flag" == "$output_id" ]; then   # only one arguement passed in for output id (i.e. no append designated)
  if [ -f $output_id ]; then
    echo "ERROR: output file $output_id already exists, please use another name or use \"append $output_id\""
    exit 99
  fi
  echo "running $2 with results written to $output_id"
else
  append_flag="$(echo $append_flag | tr '[A-Z]' '[a-z]')"     # lower case the first word of the output file ID
  if [ "$append_flag" != "append" ]; then
    echo "ERROR: first word of 3rd arguement ($append_flag) must be append or the name of the output file"
    exit 99
  else
    echo "running $2 with results appended to $output_id"
  fi
fi

glob_cpu=0
glob_l2=0
glob_l2_base="l2cache"
glob_cpu_base="qcom_pmuv3"
glob_l3_base="l3cache"
glob_l3=0
glob_valid=0
ddr_string=""
glob_ddr00=""
glob_ddr01=""
glob_ddr02=""
glob_ddr03=""
glob_ddr04=""
glob_ddr05=""

if [ -d "/sys/bus/event_source/devices/l2cache_0" ]; then
   glob_l2_base="l2cache_0"
fi

if [ -d "/sys/bus/event_source/devices/qcom_pmuv3_0" ]; then
   glob_cpu_base="qcom_pmuv3_0"
fi

if [ -d "/sys/bus/event_source/devices/l3cache_0" ]; then
   glob_l3_base="l3cache_0"
fi

first=${1%% *}     # extract first word in the string
remaining="${1#* }"  # extract all remaining words starting from the 2nd 

##########################################################################
# if the first arguement is a number, then the user wants specific events
# collected for all units (CP, L2, L3, etc.) 
##########################################################################
if expr "$first" : '[0-9][0-9]*$'>/dev/null; then   # first word is a number
     glob_cpu=1
     glob_l2=1
     glob_l3=1

     check_upfront_errors $2
     
     for n in $1
     do
       gather_events $n "$2" $output_id $4
     done
     rc=$?
     echo "event collection complete"
     exit $rc
fi

##########################################################################
# the first arguement is not a number so we need to check the keywords 
# to determine if a specific unit is of interest
##########################################################################
remaining=${remaining##*()}
if [ "$first" == "$remaining" ]; then   # only one arguement passed in
  remaining=""
fi

# first=${first,,} # lowercase the first word prior to check
first="$(echo $first | tr '[A-Z]' '[a-z]')"


if [ "$first" != "${first/cp/}" ]; then
   glob_cpu=1
   glob_valid=1
fi
if [ "$first" != "${first/l2/}" ]; then
   glob_l2=1
   glob_valid=1
fi
if [ "$first" != "${first/l3/}" ]; then
   glob_l3=1
   glob_valid=1
fi

if [ "$first" != "${first/ddr_0_0/}" ]; then
  ddr_string="${ddr_string} ddr_0_0"
  glob_valid=1
fi
if [ "$first" != "${first/ddr_0_1/}" ]; then
  ddr_string="${ddr_string} ddr_0_1"
  glob_valid=1
fi
if [ "$first" != "${first/ddr_0_2/}" ]; then
  ddr_string="${ddr_string} ddr_0_2"
  glob_valid=1
fi
if [ "$first" != "${first/ddr_0_3/}" ]; then
  ddr_string="${ddr_string} ddr_0_3"
  glob_valid=1
fi
if [ "$first" != "${first/ddr_0_4/}" ]; then
  ddr_string="${ddr_string} ddr_0_4"
  glob_valid=1
fi
if [ "$first" != "${first/ddr_0_5/}" ]; then
  ddr_string="${ddr_string} ddr_0_5"
  glob_valid=1
fi
if [[ "$first" != "${first/all/}" || "$first" != "${first/ddrs/}" ]]; then
  ddr_string=""
  if [ -d "/sys/bus/event_source/devices/ddr_0_0" ]; then
     ddr_string="${ddr_string} ddr_0_0"
     glob_valid=1
  fi
    if [ -d "/sys/bus/event_source/devices/ddr_0_1" ]; then
     ddr_string="${ddr_string} ddr_0_1"
     glob_valid=1
  fi
  if [ -d "/sys/bus/event_source/devices/ddr_0_2" ]; then
     ddr_string="${ddr_string} ddr_0_2"
     glob_valid=1
  fi
  if [ -d "/sys/bus/event_source/devices/ddr_0_3" ]; then
     ddr_string="${ddr_string} ddr_0_3"
     glob_valid=1
  fi
  if [ -d "/sys/bus/event_source/devices/ddr_0_4" ]; then
     ddr_string="${ddr_string} ddr_0_4"
     glob_valid=1
  fi
  if [ -d "/sys/bus/event_source/devices/ddr_0_5" ]; then
     ddr_string="${ddr_string} ddr_0_5"
     glob_valid=1
  fi
  if [ "$first" != "${first/all/}" ]; then
    glob_cpu=1
    glob_l2=1
    glob_l3=1
    glob_valid=1
  elif [ $glob_valid -eq 0 ]; then
    echo "ERROR: No DDR events exist on this system"
    exit 99
  fi
fi


if [ $glob_valid -eq 0 ]; then
   echo "invalid first arguement ($first)"
   exit 0
fi

set_ddr_vars $ddr_string

check_upfront_errors $2

if [ -z "$remaining" ]; then
  echo "all index request"
  gather_events -1    # get the highest index in the event list
  rc=$?
  echo " A total of $rc runs of the benchmark will be executed"
  for n in `seq 1 $rc`
  do
    gather_events $n "$2" $output_id $4
  done
  echo "event collection complete"
  exit 0
fi

for n in $remaining
do
  gather_events $n "$2" $output_id $4
done
echo "event collection complete"
rc=$?
exit $rc

echo "done."

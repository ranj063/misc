#!/bin/bash

cd /sys/kernel/debug/sof

for i in {1..2500}
do
echo "suspending iteration $i"
echo 0 > pm_debug
out=$?
if [ "$out" != "0" ]
then
	echo "suspend failure...exiting"
	exit 0
fi
sleep 1
echo "resuming iteration $i"
echo 1 > pm_debug
out=$?
if [ "$out" != "0" ]
then
	echo "resume failure...exiting"
	exit 0
fi
sleep 1
done


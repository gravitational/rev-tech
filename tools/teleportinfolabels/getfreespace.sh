#!/bin/bash


DRIVE=/dev/root

if ! [ "$1" == "" ]; then
   DRIVE=$1;
fi



SPACE_PERCENT=$(df | grep -w $DRIVE | awk '{print $5 }')
PERCENT=$(echo $SPACE_PERCENT | sed 's/%//')



if [[ $PERCENT -lt 50 ]] ; then
	SPACE_PERCENT="$SPACE_PERCENT storage 🟢";
elif [[ $PERCENT -ge 50 ]] && [[ $PERCENT -lt 90 ]] ; then
	SPACE_PERCENT="$SPACE_PERCENT storage 🟡";
else
	SPACE_PERCENT="$SPACE_PERCENT storage 🔴" ;
fi;

echo $SPACE_PERCENT




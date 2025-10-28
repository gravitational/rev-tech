#!/bin/bash

# Confirms free is available
if ! command -v free &> /dev/null
then
    echo "❓ mem info unavailable"
    exit
fi


MEMORY=$(free -m | grep Mem)
USED_MEM=$(echo "${MEMORY}" | awk '{print $3}')
TOTAL_MEM=$(echo "${MEMORY}" | awk '{print $2}')
SPACE_PERCENT=$(((USED_MEM * 100)/TOTAL_MEM))



if [[ $PERCENT -lt 50 ]] ; then
	SPACE_PERCENT="$SPACE_PERCENT% mem 🟢";
elif [[ $PERCENT -ge 50 ]] && [[ $PERCENT -lt 90 ]] ; then
	SPACE_PERCENT="$SPACE_PERCENT% mem 🟡";
else
	SPACE_PERCENT="$SPACE_PERCENT% mem 🔴" ;
fi;

echo $SPACE_PERCENT




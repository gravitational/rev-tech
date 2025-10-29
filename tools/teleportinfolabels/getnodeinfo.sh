#!/bin/bash
#usage: combines retrieval of memory % used and disk space usage


if ! [[ "$(which getfreemem.sh)" == "" ]]; then
   GETFREEMEM_INFO=$(getfreemem.sh);
else
   GETFREEMEM_INFO="❓ no memory script";
fi


if ! [[ "$(which getfreespace.sh)" == "" ]]; then
   GETFREESPACE_INFO=$(getfreespace.sh);
else
   GETFREESPACE_INFO="❓ no space script";
fi


echo "$GETFREEMEM_INFO $GETFREESPACE_INFO"

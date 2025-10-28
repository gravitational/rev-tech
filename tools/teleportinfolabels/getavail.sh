#!/bin/bash
#usage: getavail.sh <HOST> <PORT> --outputnmap

if [ "$1" == "" ] || [ "$2" == "" ]   ; then
	echo "Calls nmap to check for available service with given service type"
	echo "Usage: $(basename $0) getavail.sh <HOST> <PORT> <service type to confirm : mysql> <output map output --outputnmap>"
	exit 1
fi

# Confirms nmap is available 
if ! command -v nmap &> /dev/null
then
    echo "❓no nmap to confirm"
    exit
fi


HOST_TO_CHECK=$1
PORT_TO_CHECK=$2
FORMAT_TO_CHECK=$3

#Health output
HEALTHY_CONNECTION="Ok 🟢"
NO_CONNECTION="Unavailable ❌"
NMAP_RESULTS=$(nmap -p $PORT_TO_CHECK -Pn -sV $HOST_TO_CHECK )
if [ "$3" == "--outputnmap" ] ; then
	echo $NMAP_RESULTS;
fi ;

if echo "$NMAP_RESULTS"  | grep -i -m 1 "$PORT_TO_CHECK.*open" &> /dev/null ;then  echo "$HEALTHY_CONNECTION"; else echo "$NO_CONNECTION";  fi ;

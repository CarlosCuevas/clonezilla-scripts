#!/usr/bin/env bash

determineIfInternalOrExternalNetwork(){
	local -r ip=`ifconfig eth0 | grep "inet addr" | awk -F: '{print $2}' | awk '{print $1}' | awk '{print substr($0,1,3)}' | sed 's/ *$//g'`
	#If the first octet of the ip is 146, use 146 ip for intranet. If the first octet of the ip is 192, use 192 ip instead.
	#If neither, prompt user to specify the ip.
	if [ "$ip" = "146" ]
	then	
		echo "Network: External"
		intranet="146.245.184.84"
	elif [ "$ip" = "192" ]
	then
		echo "Network: Internal"
		intranet="192.168.2.166"
	else
		echo "Error: IP doesn't begin with 146 or 192."
		printf "Specify an ip for intranet: "
		read intranet
	fi
	echo
}

getSerial(){
	#Pull serial from machine:
	serial=`sudo dmidecode -t system | grep "Serial Number:" | awk '{print substr($0,17)}' | sed 's/ *$//g'`
	echo "Serial: $serial"
	echo
}

decrementSemaphore(){
	local decrementResult=`wget -q -O - "http://$intranet/systems/admin/ajax_controller.php?action=process_clone&serial_number=$serial&decrement=1" | head -n 1 | tail -n 1`
	if [ "$decrementResult" = "1" ]
	then
		echo "Successfully decremented semaphore."
	else
		echo "Failed to decrement semaphore.  Do it manually in the Systems Cloning web app."
	fi
}


main(){
	#global variables
	intranet=""
	serial=""

	#function calls
	determineIfInternalOrExternalNetwork
	getSerial
	decrementSemaphore
	sleep 5s
	sudo reboot	
}

main

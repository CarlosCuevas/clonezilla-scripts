#!/usr/bin/env bash

#helper functions
promptForInfo() {
	#If hostname variable is empty, prompt for hostname.
	#If not, just use the hostname.
	#If info is incorrect, hostname pulled from db is wiped out.
	local -r groupList=`wget -q -O - $pullGroupListURL | awk '{print $1}'`

	local answer=""
	while [ "$answer" != "y" ]
		do
			model=`sudo dmidecode -t system | grep "Product Name:"  | awk '{print substr($0,16)}' | sed 's/ *$//g'`
			if [[ -z $hostname ]]
			then
				echo				
				printf "Enter hostname: "
				read hostname
			else
				hostname=`wget -q -O - $pullInfoURL$serial | head -n 2 | tail -n 1`
			fi
			echo
			echo "Groups"
			PS3="Select group: "
			select opt in $groupList
			do
				if [[ -n $opt ]]
				then
					group="$opt"
					break
				else
					echo "Invalid entry"
				fi
			done
			PS3="#?"
			echo
			echo "Hostname: $hostname"
			echo "Group: $group"
			echo "Model: $model"
			echo
			printf "Info correct? [Y/n] "
			read answer
			echo
			if [ "$answer" != "y" ]
			then
				hostname=""
			fi
		done
}

promptUserToTryAgain() {
	printf "Try again? [Y/n] "
	read answer
	if [ "$answer" != "y" ]
	then
		exit
	fi
}

countdown() {
	#Function from: http://www.unix.com/shell-programming-scripting/98889-display-runnning-countdown-bash-script.html
	IFS=:
	set -- $*
	secs=$(( ${1#0} * 3600 + ${2#0} * 60 + ${3#0} ))
	while [ $secs -gt 0 ]
 	do
    	sleep 1 &
		printf "\r%02d:%02d:%02d" $((secs/3600)) $(( (secs/60)%60)) $((secs%60))
		secs=$(( $secs - 1 ))
    	wait
  	done
 	echo
}

#main functions
printBanner(){
	echo
	echo "____________________________"
	echo
	echo "Systems - Automated Restore."
	echo "____________________________"
	echo
}

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

setURLs(){
	#The only point in setting pullInfoURL, pullGroupListURL and insertURL here is the make the code more readable later on.

	#Set url to pull info from:
	pullInfoURL="http://$intranet/systems/ajax/ajax_index.php?query=modelImages&serial_number="
	#Set url to pull groups from:
	pullGroupListURL="http://$intranet/systems/ajax/ajax_index.php?query=groups&type=text"
	#set url for insert:
	insertURL="http://$intranet/systems/admin/ajax_controller.php?action=add_custom_computer_group&serial_number="	
}

getSerial(){
	#Pull serial from machine:
	serial=`sudo dmidecode -t system | grep "Serial Number:" | awk '{print substr($0,17)}' | sed 's/ *$//g'`
	echo "Serial: $serial"
	echo
}

checkIfMachineIsInDatabase(){
	#	This is nested in a while loop because if the info is missing, the script will prompt the user for the info,
	#	update the db and then attempt to pull again (i.e. repeat the loop). This ensures the info is in the database for when step1 & step2 run later on.
	
	#DB Return Status Values:
	#	0 : All info found in db.
	#	1 : Either the machine is completely missing from the db (1 followed by a -) or it is in the db but has no group association (1 followed by hostname).
	#	2 : Blank serial sent to db.
	#	3 : No image associated with that group and model.
	
	#Some Return Data Examples:
	
	#	0
	#	NMC
	#	LB-SOMEPORT-2C-23
	#	760_PUBLIC_10-22-14
	
	#	1
	#	-
	
	#	1
	#	LB-Carlos-PC

	local insertReturnStatus=""
	local pullInfoRawData=""
	local pullInfoStatus=""
	local pullInfoArray=""

	local proceed=false
	while [ $proceed = false ]
	do
		pullInfoRawData=`wget -q -O - $pullInfoURL$serial`
		IFS=$'\n' read -rd '' -a pullInfoArray <<< "$pullInfoRawData" #create array from return data
		pullInfoStatus="${pullInfoArray[0]}"		
		if [ "$pullInfoStatus" = "0" ]
		then
			echo "All Info Found."
			hostname="${pullInfoArray[2]}"
			echo "Hostname: $hostname"
			group="${pullInfoArray[1]}"
			echo "Group: $group	"
			image="${pullInfoArray[3]}"
			echo "Image: $image"
			sleep 2s
			proceed=true
		elif [ "$pullInfoStatus" = "1" ]
		then
			dashOrHostname="${pullInfoArray[1]}"
			if [ "$dashOrHostname" != "-" ]
			then
				hostname="$dashOrHostname"
				echo "Group info missing."
				echo "Hostname: $hostname"
			else
				echo "No record in the database for that machine."
			fi
			promptForInfo
			#insert to DB
			insertReturnStatus=`wget -q -O - "$insertURL$serial&computer_name=$hostname&model_name=$model&group_name=$group"`
			if [ "$insertReturnStatus" != "Success" ]
			then
				echo "Update $insertReturnStatus" #Error
				promptUserToTryAgain
			else
				echo "Database update succeeded."
			fi
			echo
		elif [ "$pullInfoStatus" = "2" ] 
		then
			echo "Error: Blank serial was sent to the database."
			promptUserToTryAgain
			serial=`sudo dmidecode -t system | grep "Serial Number:" | awk '{print substr($0,17)}' | sed 's/ *$//g'`
		elif [ "$pullInfoStatus" = "3" ]
		then
			echo "Error: No image associated with this Group and Model."
			echo "Clonezilla will prompt you to choose an image from the share."
			echo
			image="ask_user"
			sleep 5s
			proceed=true
		else
			echo "Error: Return data from database doesn't correspond to any expected values.  Is the database down?"
			promptUserToTryAgain
		fi
	done
}

checkSemaphore() {
	local semaphoreStatus=""
	#Ask db for amount of time script should wait before trying again.  We ask for it here (even though it's potentially unnecessary) so we don't ask over and over in the loop.
	local -r waitToTryAgain=`wget -q -O - "http://$intranet/systems/ajax/ajax_index.php?query=settings&setting_name=waitToTryAgain"`

	#Only proceed when a slot opens.
	local proceed=false
	while [ "$proceed" = false ]
	do
		#Query semaphore for open slot.
		semaphoreStatus=`wget -q -O - "http://$intranet/systems/admin/ajax_controller.php?action=process_clone&serial_number=$serial&increment=1"  | head -n 1 | tail -n 1`
		if [ "$semaphoreStatus" = "1" ]
		then
			#A slot is open. Count was incremented on the server and cloning can proceed.
			echo "Successfully incremented semaphore."
			echo
			proceed=true
		elif [ "$semaphoreStatus"	= "Error: Computer-Group does not exist" ] #why is this even a possibilty? this needs review.
		then
			#This, in theory, should never occur (a group would've had to be entered to even make it this far in the script). It's here for the sake of thoroughness.
			echo "$semaphoreStatus"
			exit 1
		else
			#If 0, no slots are open.  Wait as many minutes as are in $waitToTryAgain before trying again.
			echo "Too many machines already cloning.  Waiting $waitToTryAgain minutes for a free slot."
			countdown 00:$waitToTryAgain:00
			echo
		fi
	done
}

startCloning(){
	ocs-sr -g auto -e1 auto -e2 -batch -r -j2 -p true restoredisk $image sda
}

main(){
	
	#some global variables
	image=""
	intranet=""
	serial=""
	group=""
	hostname=""
	pullInfoURL=""
	pullGroupListURL=""
	insertURL=""	

	#function calls
	printBanner
	determineIfInternalOrExternalNetwork #can't rely on DNS to provide the appropriate IP
	setURLs
	getSerial
	checkIfMachineIsInDatabase
	checkSemaphore
	startCloning

}

main

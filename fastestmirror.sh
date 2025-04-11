#####
## fastestmirror.sh
## finalduty 19/12/12
##
## This script is used to test for the fastest ping to ALARMPI mirrors.
## You can also have it automatically write to your mirrorlist
#####

#!/bin/bash

## Creates .tmp file if it doesn't exist and writes a blank line into it. (Useful if the script is cancelled before the rm function)
touch .massping.tmp
echo -n > .massping.tmp

## Collect the mirrors from /etc/pacman.d/mirrorlist, strip them and enter them into the $mirrors array
mirrors=$(cat /etc/pacman.d/mirrorlist | grep "Server =" | sed 's/^.*\=//')

## Loop through the array values and query them and ping them.
for i in ${mirrors[@]}; do

        ## Show > symbol to indicate progress and write the URL to temporary file without a newline
        echo -n ">" && echo -n $i >> .massping.tmp

        ## Ping the actual server, retrieve the average from the last line, strip it and write to the temporary file
        ping -fc5 $(echo $i | awk -F '/' '{print $3}') | tail -1| awk -F '/' '{print " " $5 " ms"}' >> .massping.tmp
done

## Set variable $fastest by sorting the temp file based off numerical pings, removes blanks/timeouts and returns the top value.
fastest=$(sort -nk2 .massping.tmp | grep -v "repo  ms" | head -1)

## Prints to screen the fastest average ping in green and clears color formatting, ready for next output
echo && echo -e "\e[0;32m"$fastest && tput sgr0

## Sorts the temporary file and outputs all but the fastest result (because it has already been printed in colour)
sort -nk2 .massping.tmp | grep -v "repo  ms" | tail -n+2

## Tidy up - Remove Temporary File
rm .massping.tmp

## Strip the ping time from the $fastest variable so we can search for it in the mirrors list
fast=$(echo $fastest | sed 's/ .*$//')


# WARNING - UNCOMMENTING BELOW THIS LINE WILL CAUSE CHANGES TO BE WRITTEN TO YOUR MIRRORLIST
# PLEASE MAKE SURE THAT YOU UNDERSTAND THE SCRIPT BEFORE ALLOWING THIS.
# USE AT YOUR OWN RISK AND MAKE SURE YOU TAKE A BACKUP. I WILL NOT CONSOLE YOU WHEN YOU CRY

## Comments all uncommented "Server =" entries in /etc/pacman.d/mirrorlist
sed -i 's/^.*Server/\# Server/' /etc/pacman.d/mirrorlist

## Uncomments only the fastest server in /etc/pacman.d/mirrorlist
sed -i "s|^# Server = $fast|Server = $fast|" /etc/pacman.d/mirrorlist && echo && echo "Server "$fast" has been set as the default mirror"

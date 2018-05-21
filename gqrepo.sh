#!/bin/bash
#
PASSWD=$(zenity --entry --hide-text --text="Enter Root Password" --title=Authentication)
echo -e $PASSWD | su -c "true"
if [[ $? == 1 ]]; then
	zenity --error --text="An error occurred: Wrong Password\! \\n" --width=150 --title="Warning\!"
	exit 1
fi
while  [[ $? == 0 ]]; do
oldifs=$IFS
IFS=','
repo_file=($(ls -H /etc/yum.repos.d/*.repo| tr '\n' ','))
file_chose=$(zenity --list --cancel-label="Exit" --title="Repo List" --width=640 --height=480 --column="File Path" "${repo_file[@]}")
if [[ -z ${file_chose} ]]; then
   exit 0
fi
repo_select=($(grep -h '\[.*.\]\|enabled=' ${file_chose}|tr '\n' ','|tr -d '[:space:]'))
IFS=$oldifs
repo_chose=$(zenity --list --title="Repo List" --width=640 --height=480 --column="Name" --column="Enabled" --separator=':' --print-column="1,2" "${repo_select[@]}"|sed 's/[][]//g')
repo_name=$(echo $repo_chose|cut -d: -f1)
repo_state=$(echo $repo_chose|cut -d':' -f2|cut -d'=' -f2)
if [ "${repo_state}" == "0" ]; then
	echo -e $PASSWD | su -c "dnf config-manager --set-enabled ${repo_name}"
elif [ "${repo_state}" == "1" ]; then
	echo -e $PASSWD | su -c "dnf config-manager --set-disable ${repo_name}"

fi
done

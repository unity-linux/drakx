#!/bin/bash
# Requires: wmctrl

#Vars
num_args=${#}
# Qarma is an option to but lacks stdin parsing with #
gui_prog=zenity

# We have to have packages to install
if test "${num_args}" -lt 1; then
    echo "Enter more then: ${num_args} of parameters"
    exit 1
fi

# Force Progress Bar to always be on top.
sleep 1 && wmctrl -r "Install Status" -b add,above &

install_pkgs () {
	pkg=${1}
	perc=${2}
	echo "${perc}"
	echo "# Installing package ${pkg}" ; sleep 2
	dnf -y install ${pkg}
}

(
# =================================================================

if test "${num_args}" -eq 1; then
	install_pkgs ${1} 50
	exit 0
else

for num in $(eval echo "{1..${num_args}}"); do
	eval "arg=\${$num}"
	perc=$((100*${num}/${num_args}))
	install_pkgs ${arg} ${perc}
done
fi

# =================================================================
echo 100
echo "# All finished." ; sleep 2

) |
${gui_prog} --progress \
  --title="Install Status" \
  --text="Package Install Progress." \
  --percentage=0 \
  --auto-close \
  --auto-kill

(( $? != 0 )) && ${gui_prog} --error --text="Error in gui command."

exit 0

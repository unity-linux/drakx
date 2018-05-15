#!/bin/sh

# enable loadkeys to work before manually starting drakx in debug env:
export SHARE_PATH=/usr/share
echo "Starting Udev\n"
perl -I/usr/lib/libDrakX -Minstall::install2 -e "install::install2::start_udev()"
echo "You can start the installer by running install2"
echo "You can run it in GDB by running gdb-inst"
export GUILE_AUTO_COMPILE=0
/usr/bin/busybox sh
exec install2 $@

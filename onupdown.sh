#!/bin/sh
# onupdown.sh
# Runs makesnapshot.sh on system suspend or powerdown with user interaction.
# Allows the user to skip it, for example if in a hurry, intended for laptop
# usage.
#
# 2015-06, Ingo Bressler <dev@ingobressler.net>
# Works for the author on Ubuntu 14.04.
# USED WITH EXTREME CARE, DATA LOSS MAY OCCUR, NO WARRANTY!
# License: GPLv3

MAKESNAPSHOT="/usr/local/bin/makesnapshot.sh"
LOGFILE="/var/log/snapshot.log"

TIMEOUT=3
DELAYFINALLY=5
XMESSAGE="/usr/bin/xmessage"
XMESSAGEOPTS="-center -default no -buttons yes:0,no:1 -timeout ${TIMEOUT} -file -"
ECHO="/bin/echo"
TEE="/usr/bin/tee"
BASH="/bin/bash"
# xterm compatible terminal emulator for log output
#TERM="/usr/bin/x-terminal-emulator"
TERM="/usr/bin/xterm"
TERMFONT="-fa Monospace -fs 10"
TERMTITLE="Creating snapshots ..."
TERMGEOM="120x20+300+300"
SLEEP="/bin/sleep"

on_abort()
{
  $ECHO "Skipping creating new snapshots."
}

on_accept()
{
  $ECHO "### $(date)" >> "${LOGFILE}"
  ${TERM} ${TERMFONT} -geometry ${TERMGEOM} -title "${TERMTITLE}" -e $BASH \
    -c "${MAKESNAPSHOT} 2>&1 | $TEE -a "${LOGFILE}"; $SLEEP $DELAYFINALLY"
}

run()
{
  if ${XMESSAGE} ${XMESSAGEOPTS} <<EOF
Create snapshots of current system state?

Continuing in ${TIMEOUT} seconds.
Press <enter> to abort.
EOF
  then
    on_accept
  else
    on_abort
  fi
}
run

# vim: set ts=2 sts=2 sw=2 tw=0:

#!/bin/sh
# onupdown.sh
# Runs makesnapshot.sh on system suspend or powerdown with user interaction.
# Allows the user to skip it, for example if in a hurry, intended for laptop
# usage.
#
# To be placed in /etc/pm/sleep.d/
#
# 2015-06, Ingo Bressler <dev@ingobressler.net>
# Works for the author on Ubuntu 14.04.
# USED WITH EXTREME CARE, DATA LOSS MAY OCCUR, NO WARRANTY!
# License: GPLv3

MAKESNAPSHOT="/usr/local/bin/makesnapshot.sh"
LOGFILE="/var/log/snapshot.log"

TIMEOUT=10
DELAYFINALLY=10
DISPLAY=":0"
XMESSAGE="/usr/bin/xmessage"
XMESSAGEBUTTONS="-buttons yes:0,no:1 -default no -timeout ${TIMEOUT}"
XMESSAGEOPTS="-display ${DISPLAY} -center ${XMESSAGEBUTTONS} -file -"
ECHO="/bin/echo"
TEE="/usr/bin/tee"
BASH="/bin/bash"
# xterm compatible terminal emulator for log output
#TERM="/usr/bin/x-terminal-emulator"
TERM="/usr/bin/xterm"
TERMFONT="-fa Monospace -fs 10 -display ${DISPLAY}"
TERMTITLE="Creating snapshots ..."
TERMGEOM="120x20+300+300"
SLEEP="/bin/sleep"
HEAD="/usr/bin/head"
PS="/bin/ps"
GREP="/bin/grep"
AWK="/usr/bin/awk"
SUDO="/usr/bin/sudo"

on_abort()
{
  $ECHO "Skipping creating new snapshots."
}

on_accept()
{
  local xuser="$1"
  # start snapshot creation in background, has to be run as root
  (${MAKESNAPSHOT}; $SLEEP $DELAYFINALLY) &
  # run terminal with snapshot log output
  # in foreground by user owning the X session
  # the tail command within (and this function) exists when the above delay is over
  $SUDO -u "$xuser" ${TERM} ${TERMFONT} -geometry ${TERMGEOM} \
    -title "${TERMTITLE}" -e $BASH \
    -c "/usr/bin/tail --pid="$!" -f ${LOGFILE}"
}

get_xuser()
{
  $PS --no-headers -o user,cmd -C init \
    | $GREP -- --user \
    | $AWK '{print $1}' \
    | $HEAD -n1
}

raise_message()
{
  local xuser="$1"
  $SUDO -u "$xuser" ${XMESSAGE} ${XMESSAGEOPTS} <<EOF
Create snapshots of current system state?

Continuing in ${TIMEOUT} seconds.
Press <enter> to abort.
EOF
}

run()
{
  local xuser="$(get_xuser)"
  $ECHO "   ### $(date)" # start new section in log file
  if raise_message "${xuser}"
  then
    on_accept "${xuser}"
  else
    on_abort
  fi
}

# For /etc/pm/sleep.d/
case "${1}" in
        suspend|suspend_hybrid|hibernate)
          $SLEEP 1 # delay is important to let the restart/suspend selector UI vanish
          run 2>&1 | $TEE -a "$LOGFILE"
        ;;
        resume|thaw)
          # Nothing to do here
        ;;
        *)
        ;;
esac
exit 0

# vim: set ts=2 sts=2 sw=2 tw=0:

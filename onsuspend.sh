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

get_xsession()
{
  local username="$($PS --no-headers -o user,cmd -C init \
                       | $GREP -- --user \
                       | $AWK '{print $1}' \
                       | $HEAD -n1)"
  local userhome="$(/bin/su -c "$ECHO \$HOME" $username)"
  local xauthfn="$userhome/.Xauthority"
  if [ ! -f "${xauthfn}" ]
  then
    $ECHO "Xauthority not found for starting xmessage window: '${xauthfn}'!"
    return
  fi
  /bin/cp "${xauthfn}" "${xauthfn_root}"
}

release_xsession()
{
  rm -f "${xauthfn_root}"
}

run()
{
  xauthfn_root="/root/.Xauthority"
  get_xsession
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
  release_xsession
}

# For /etc/pm/sleep.d/
case "${1}" in
        suspend|suspend_hybrid|hibernate)
          run
        ;;
        resume|thaw)
          # Nothing to do here
        ;;
        *)
        ;;
esac
exit 0

# vim: set ts=2 sts=2 sw=2 tw=0:

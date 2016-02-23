#!/bin/sh
#
# let udev run this script
# ACTION=="add", ATTRS{idVendor}=="****", ATTRS{idProduct}=="****", RUN+="/usr/local/my_script.sh"
#
# references:
# "Autorun a script after I plugged or unplugged a USB device"
# http://askubuntu.com/q/284224
# "Running a Script on connecting USB device"
# http://askubuntu.com/q/401390

udev_rule="/etc/udev/rules.d/99-backup-storage.rules"
LOGFILE="/var/log/onudevadd.log"

ECHO="/bin/echo"
WHOAMI="/usr/bin/whoami"
UDEVADM="/sbin/udevadm"
AWK="/usr/bin/awk"
GREP="/bin/grep"
TEE="/usr/bin/tee"

check_su()
{
  if [ "x$($WHOAMI)" != "xroot" ]
  then
    $ECHO "Need to be run as root, sorry."
    exit 0
  fi
}

usage_help()
{
  cat <<EOF
Usage: $script_name <cmd> <argument>
The following commands are defined:
  install <dev>
    Creates an udev rules file which calls this script when the device
    specified by <dev> (a block/usb device file in /dev/*) is connected,
    based on its serial number:
    '$udev_rule'
    Warning: it OVERWRITES an existing file with the same name!
  udev_on_add
    Starts the 'on_add' command in background. For use in udev rules.
  on_add
    Actually starts some <action> when the device specified by the
    'install' command is connected.
    For these actions, superuser permissions are required (to be run by udev).
EOF
  exit 1
}

install()
{
  if [ ! -x "$UDEVADM" ]; then
    $ECHO "Can not install, $UDEVADM not found!"
    return
  fi
  dev_name="$1"
  if [ ! -b "$dev_name" ]; then
    $ECHO "Can not install, provided device is not a block device! ('$dev_name')"
    return
  fi
  serial="$($UDEVADM info --name "$dev_name" | \
            $GREP 'ID_SERIAL_SHORT=' | \
            $AWK -F'=' '{print $2}')"
  # wildcard: ATTRS{idVendor}=="****", ATTRS{idProduct}=="****",'\
  # "ATTRS{idVendor}==\"$vendor_id\", ATTRS{idProduct}==\"$product_id\","\
  rule="$($ECHO 'ACTION=="add",'\
    "ATTRS{serial}==\"$serial\","\
    'SUBSYSTEM=="block", ENV{DEVTYPE}=="disk",'\
    "RUN+=\"$script_path udev_on_add\"")"
  $ECHO -e "  adding:\n${rule}\n  to:\n${udev_rule}"
  $ECHO "$rule" > "$udev_rule"
  chmod 644 "$udev_rule"
  [ -x "$UDEVADM" ] && "$UDEVADM" control --reload-rules
}

mount()
{
  $ECHO mount
}

umount()
{
  $ECHO umount
}

do_backup()
{
  $ECHO do_backup
}

MOUNT="/bin/mount"
UMOUNT="/bin/umount"
SLEEP="/bin/sleep"
HEAD="/usr/bin/head"
PS="/bin/ps"

TERM="/usr/bin/xterm"
DISPLAY=":0"
TERMFONT="-fa Monospace -fs 10 -display ${DISPLAY}"
TERMGEOM="120x20+300+300"
TERMTITLE="Creating snapshots ..."
#  $SUDO -u "$xuser" ${TERM} ${TERMFONT} -geometry ${TERMGEOM} \
#    -title "${TERMTITLE}" -e $BASH \
#    -c "/usr/bin/tail --pid="$!" -f ${LOGFILE}"

DELAY_EXIT=5 # wait a moment to let the user read log messages

XHOST="/usr/bin/xhost"
SUDO="/usr/bin/sudo"

get_xuser()
{
  $PS --no-headers -o user,cmd -C init \
    | $GREP -- --user \
    | $AWK '{print $1}' \
    | $HEAD -n1
}

xhost_add_user()
{
  local username="$1"
  local xuser="$(get_xuser)"
  $SUDO -u $xuser DISPLAY=$DISPLAY $XHOST +SI:localuser:$username > /dev/null
}

xhost_remove_user()
{
  local username="$1"
  local xuser="$(get_xuser)"
  $SUDO -u $xuser DISPLAY=$DISPLAY $XHOST -SI:localuser:$username > /dev/null
}

on_exit()
{
  xhost_remove_user root
  $ECHO "Log output was written to '$LOGFILE'."
  #$SLEEP $DELAY_EXIT
  read -p "Press return to close this window ..." dummy
  $ECHO # line break
  exit $@
}

on_add()
{
  $ECHO "=== $(date) ==="
  if [ ! -b "$DEVNAME" ]; then
    $ECHO "Given device '$DEVNAME' not found!"
    on_exit 1 # device not found
  fi
  $SLEEP 5
  env
  $ECHO "Making sure the device is not mounted:"
  for dname in ${DEVNAME}*; do
    $ECHO "  Unmounting '$dname' ..."
    $UMOUNT "$dname"
  done
  $ECHO done
  on_exit 0
}

run()
{
  if ([ $# -eq 0 ] || [ "x$1" = "x--help" ] || [ "x$1" = "x-h" ]); then
    usage_help
  fi
  check_su
  cmd="$1"
  shift 1
  case "$cmd" in
    install) install $@ ;;
    # let udev launch this script in background
    # run() redirects logging internally before it vanishes in /dev/null
    udev_on_add)
      xhost_add_user root
      nohup ${TERM} ${TERMFONT} -geometry ${TERMGEOM} \
         -title "${TERMTITLE}" \
         -e "$script_path on_add" > /dev/null 2>&1 & ;;
    on_add) on_add ;;
  esac
}

script_name="$(basename "$0")"
script_path="$(cd "$(dirname "$0")" && pwd)/$script_name"

if [ -w "$LOGFILE" ]; then
  run "$@" 2>&1 | $TEE -a "$LOGFILE"
else
  run "$@" 2>&1
fi

# vim: set ts=2 sts=2 sw=2 tw=0:

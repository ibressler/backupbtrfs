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
# usb key for testing:
vendor_id="090c"
product_id="1000"

ECHO="/bin/echo"
WHOAMI="/usr/bin/whoami"
UDEVADM="/sbin/udevadm"
AWK="/usr/bin/awk"
GREP="/bin/grep"

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
Usage: $script_name <cmd>
  The following commands are defined:
  install - Creates an udev rules file which calls this script when an
            usb storage device is connected:
            '$udev_rule'
            Warning: it OVERWRITES an existing file with the same name!
For these actions, superuser permissions are required.
EOF
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
    "RUN+=\"$script_path onadd\"")"
  $ECHO -e " -> adding:\n${rule}\n -> to:\n${udev_rule}"
  $ECHO "$rule" > "$udev_rule"
  chmod 644 "$udev_rule"
  [ -x "$UDEVADM" ] && "$UDEVADM" control --reload-rules
}

onadd()
{
  tmpfn="/tmp/tmpenv"
  date >> $tmpfn
  env >> $tmpfn
  $ECHO >> $tmpfn
  $ECHO tmpfn: $tmpfn
}

run()
{
  check_su
  cmd="$1"
  shift 1
  case "$cmd" in
    install) install $@;;
    onadd) onadd;;
  esac
}

script_name="$(basename "$0")"
script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

if ([ $# -eq 0 ] || [ "x$1" = "x--help" ] || [ "x$1" = "x-h" ]); then
  usage_help
fi

run "$@"

# vim: set ts=2 sts=2 sw=2 tw=0:

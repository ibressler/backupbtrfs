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
LOG_MAX_LINES=2000 # initially wipe old log entries up to this number of lines

ECHO="/bin/echo"
BTRFS="/bin/btrfs"
MKDIR="/bin/mkdir"
RMDIR="/bin/rmdir"
DATE="/bin/date"
WHOAMI="/usr/bin/whoami"
UDEVADM="/sbin/udevadm"
AWK="/usr/bin/awk"
GREP="/bin/grep"
TEE="/usr/bin/tee"

MOUNT="/bin/mount"
UMOUNT="/bin/umount"
SLEEP="/bin/sleep"
HEAD="/usr/bin/head"
PS="/bin/ps"
LS="/bin/ls"
WC="/usr/bin/wc"
MKTEMP="/bin/mktemp"
EJECT="/usr/bin/eject"

CP="/bin/cp"
RM="/bin/rm"
TAIL="/usr/bin/tail"

#TERM="/usr/bin/xterm"
TERM="/usr/bin/x-terminal-emulator"
DISPLAY=":0"
TERMFONT="-fa Monospace -fs 10"
TERMGEOM="120x20+300+300"
TERMTITLE="Backup storage connected ..."

EXIT_DELAY=5 # wait a moment to let the user read log messages
PREFIX=" ==>"

XHOST="/usr/bin/xhost"
SUDO="/usr/bin/sudo"

TRUECRYPT="/usr/bin/truecrypt"
TC_FS="btrfs"
TC_FS_OPTS="defaults,noauto,noatime,nodiratime,compress-force=lzo"
HDPARM="/sbin/hdparm"
STDBUF="/usr/bin/stdbuf"

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
    Mounts the device or the first partition, if found, via truecrypt using
    the file system '$TC_FS' with the following options:
    '$TC_FS_OPTS'.
For these actions, superuser permissions are required (to be run by udev).
EOF
  exit 1
}

SIMULATE=0
# modify global settings
if [ "$SIMULATE" -eq "1" ]; then
  MKTEMP="$MKTEMP -u"
fi

sim()
{
  local is_sim="$SIMULATE"
  if [ "x${1}x" = x1x ]; then
    shift 1
    local is_sim=1
  fi
  if [ "x${1}x" = x0x ]; then
    shift 1
    local is_sim=0
  fi
  if [ "$is_sim" -eq "1" ]; then
    $ECHO "$@"
  else
    $@
  fi
  return $?
}

install()
{
  if [ ! -x "$UDEVADM" ]; then
    $ECHO "Can not install, $UDEVADM not found!"
    return
  fi
  local devname="$1"
  if [ ! -b "$devname" ]; then
    $ECHO "Can not install, provided device is not a block device! ('$devname')"
    return
  fi
  serial="$($UDEVADM info --name "$devname" | \
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
  #$SLEEP $EXIT_DELAY
  read -p "Press return to close this window ..." dummy
  $ECHO # line break
  exit $@
}

get_partition() 
{
  local devname="$1"
  [ -b "$devname" ] || return
  local count="$($LS -1 "$devname"* | $WC -l)"
  if [ "$count" -lt 2 ]; then
    $ECHO "$devname"
    return
  fi
  local part="$($LS -1 "$devname"* | $GREP -v "$devname$" | $HEAD -n1)"
  if [ -b "$part" ]; then
    $ECHO "$part"
  fi
}

mount_or_umount()
{
  local cmd="$1"
  local devname="$2"
  local mountpoint="$3"
  local mountpart="$(get_partition "$devname")"
  [ -b "$mountpart" ] || return
  case "$cmd" in
    mount) 
      # stdbuf disables stdout buffering for truecrypt,
      # otherwise the password prompt is not shown
      sim $STDBUF -o 0 $TRUECRYPT -t --protect-hidden=no --keyfiles= \
        --filesystem="$TC_FS" \
        --fs-options="$TC_FS_OPTS" \
        --mount "$mountpart" "$mountpoint" 2>&1
      ;;
    umount)
      # unmount and put drive to sleep via hdparm -Y
      # (avoids emergency stop at hot-unplug)
      sim $STDBUF -o 0 $TRUECRYPT -t -d "$mountpart" 2>&1
      read -p "Press <enter> to put '$devname' to sleep ('n' aborts): " do_sleep
      if [ -x "$HDPARM" -a -z "$do_sleep" ]; then
        sim $HDPARM -Y "$devname" && \
        $ECHO "$PREFIX It is now safe to unplug the device."
        $EJECT "$devname"
      fi
      ;;
  esac
}

format_elapsed_secs()
{
  local elapsed="$1"
  local hours="$(($elapsed/3600))"
  local min="$((($elapsed-($hours*3600))/60))"
  local secs="$(($elapsed-($hours*3600)-($min*60)))"
  $ECHO "${hours}h ${min}m ${secs}s"
}

# local mount point under which the timestamp directories for each backup can
# be found; it is expected to be configured in /etc/fstab
BACKUP_SOURCE="/mnt/root"

do_backup()
{
  $ECHO do_backup $@
  local dest="$1"
  local src="$2"
  [ -d "$dest" ] || return
  [ -z "$src" ] && return
  # get the name of the previous snapshot on external storage
  # assuming alpha numerical sorting, inversed order: newest on top
  local prev="$(cd "$dest" && $LS -1r | \
                              $GREP -E '^@[0-9]+' | \
                              $HEAD -n1 | \
                              $AWK -F'@' '{print $2}')" # strip leading @
  if [ -z "$prev" ]; then
    $ECHO "Previous snapshots name not found!"
    return
  fi
  echo "Previous snapshots:       '$prev'"
  # create source mount point if necessary
  [ -d "$src" ] || sim $MKDIR "$src"
  if ! $MOUNT | $GREP -q " $src "; then
    # mount source if not already mounted, expected to be in /etc/fstab
    $ECHO "Mounting '$src' ..."
    sim $MOUNT "$src"
  fi
  # in order to get the next snapshot name, find the previous one in the
  # source directory and chose the one above, assuming alnum sorting
  # (see above)
  local next="$(cd "$src" && $LS -1r | \
                             $GREP -E '^@[0-9]+' | \
                             $GREP -B1 "$prev" | \
                             $HEAD -n1 | \
                             $AWK -F'@' '{print $2}')" # strip leading @
  if [ -z "$next" ]; then
    $ECHO "Next snapshots name not found!"
    return
  fi
  if [ "$next" = "$prev" ]; then
    $ECHO " => No newer snapshots found, creating new ones ..."
  fi
  echo "Next snapshots to backup: '$next'"
  # btrfs backup, differential between $prev and $new
  local elapsed_sum=0
  local btrfs_sim=0
  local IFS=$'
'
  for subpath in $($BTRFS sub list "$src" 2>&1 | \
                   $GREP "$next" | \
                   $AWK -F' @' '{print $2}')
  do
    local subpath="@$subpath"
    $ECHO " Processing '$subpath' ..."
    local basepath="${subpath%/*}"
    sim $btrfs_sim $MKDIR -p "$dest/$basepath"
    sim $btrfs_sim $BTRFS property set "$src/$subpath" ro true
    local ts=$($DATE +%s)
    local oldpath="$src/@$prev/${subpath#*/}"
    if [ -d "$oldpath" ]; then
      sim $btrfs_sim $BTRFS send -v -p "$oldpath" "$src/$subpath" | \
                     $BTRFS rec -v "$dest/$basepath"
    else
      sim $btrfs_sim $BTRFS send -v "$src/$subpath" | $BTRFS rec -v "$dest/$basepath"
    fi
    local elapsed="$(($($DATE +%s) - $ts))"
    local elapsed_sum="$(($elapsed_sum + $elapsed))"
    $ECHO "$PREFIX done in $(format_elapsed_secs $elapsed)"
  done
  $ECHO "$PREFIX Overall time: $(format_elapsed_secs $elapsed_sum)"
}

on_add()
{
  $ECHO "=== $(date) ==="
  [ -b "$DEVNAME" ] || DEVNAME="$1"
  if [ ! -b "$DEVNAME" ]; then
    $ECHO "Given device '$DEVNAME' not found!"
    on_exit 1 # device not found
  fi
  $SLEEP 5 # DELAY to let the drive settle, auto-mount or similar
  $ECHO "Making sure the device is not mounted:"
  for dname in ${DEVNAME}*; do
    $ECHO "  Unmounting '$dname' ..."
    sim $UMOUNT "$dname"
  done
  if [ ! -x "$TRUECRYPT" ]; then
    $ECHO "Truecrypt binary '$TRUECRYPT' is not executable or not found!"
    on_exit 1
  fi
  local mountpoint="$($MKTEMP -d --tmpdir=/mnt)"
  mount_or_umount mount "$DEVNAME" "$mountpoint"
  $SLEEP 1 # DELAY to let the mounted fs settle, not sure if required
  do_backup "$mountpoint" "$BACKUP_SOURCE"
  mount_or_umount umount "$DEVNAME" "$mountpoint"
  sim $RMDIR --ignore-fail-on-non-empty "$mountpoint"
  $ECHO done.
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
      DISPLAY="$DISPLAY" \
      nohup ${TERM} ${TERMFONT} -geometry ${TERMGEOM} \
         -title "${TERMTITLE}" \
         -e "$script_path on_add" > /dev/null 2>&1 & ;;
    on_add) on_add $@ ;;
  esac
}

truncate_file()
{
  local fpath="$1"
  [ -w "$fpath" ] || return # no write access
  local ftmp=$($MKTEMP)
  $TAIL -n $LOG_MAX_LINES "$fpath" > "$ftmp"
  $CP "$ftmp" "$fpath"
  $RM "$ftmp"
}

script_name="$(basename "$0")"
script_path="$(cd "$(dirname "$0")" && pwd)/$script_name"

if [ -w "$LOGFILE" ]; then
  truncate_file "$LOGFILE"
  run "$@" 2>&1 | $TEE -a "$LOGFILE"
else
  run "$@" 2>&1
fi

# vim: set ts=2 sts=2 sw=2 tw=0:

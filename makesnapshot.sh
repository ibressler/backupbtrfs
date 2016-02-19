#!/bin/sh
# makesnapshot.sh
# Creates btrfs snapshots of filesystems on multiple devices based on
# a common time stamp.
# Requires a mount point for the root of each file system being specified
# in /etc/fstab. It is mounted as needed.
#
# Further documentation can be found in enclosed README.md
#
# originally from:
# https://wiki.archlinux.org/index.php/Btrfs_-_Tips_and_tricks
# modifed 2015-06, Ingo Bressler <dev@ingobressler.net>
#
# Works for the author on Ubuntu 14.04.
# USE WITH EXTREME CARE, DATA LOSS MAY OCCUR, NO WARRANTY!
# License: GPLv3

# Can be provided as command line argument
root_volume_name="@"
days_to_keep=30
time_delta_secs=$((${days_to_keep} * 24 * 3600))
#time_delta_secs=80 # for debugging
# minimum number of snapshots to keep, irrespective of the timestamp
count_to_keep=3
timestamp_path="/SNAPSHOT-TIMESTAMP"
this_script="${0}"

GRUBCFG="/boot/grub/grub.cfg" # source for menu entry pattern
GRUBCTM="/etc/grub.d/40_custom" # target for menu entries
# sys command for regenerating grub menu with contents of $GRUBCTM file
UPDATE_GRUB="/usr/sbin/update-grub"

ECHO="/bin/echo"
BTRFS="/bin/btrfs"
AWK="/usr/bin/awk"
SED="/bin/sed"
DIRNAME="/usr/bin/dirname"
DATE="/bin/date"
SYNC="/bin/sync"
MKDIR="/bin/mkdir"
GREP="/bin/grep"
MOUNT="/bin/mount"
UMOUNT="/bin/umount"
SORT="/usr/bin/sort"
UNIQ="/usr/bin/uniq"
CHKSUM="/usr/bin/sha1sum"

if [ "x$(whoami)" != "xroot" ]
then
  $ECHO "Need to be run as root, sorry."
  exit 0
fi

# take no snapshots when booted into a snapshot
if [ -e "${timestamp_path}" ]
then
  exit 0
fi

# returns a list of subvolume names for the given btrfs mount point
# lexicographically inverse sorted: most recent timestamps first
get_subvolumes()
{
  local btrfs_root="${1}"
  btrfs subvolume list -q "${btrfs_root}" | \
  case "${2}" in
    parent)   $GREP 'parent_uuid -' ;;
    noparent) $GREP -v 'parent_uuid -' ;;
    *)        $GREP '' ;;
  esac | \
    $AWK '{print $NF}' | \
    $SORT -r
}
format_timestamp()
{
  local delta="${1}" # seconds earlier than now
  if [ ! -z "$delta" ]; then
    delta="--date=@$(($($DATE +%s) - $delta))"
  fi
  echo -n "$($DATE +%Y-%m-%d_%H%M%S $delta)"
}
current_issue()
{
  local fn="${1}"
  $AWK '/^[A-Z]+/{print $1" "$2" "$3}' "${fn}"
}
sed_escape_path()
{
  local inpath="${1}"
  $ECHO "${inpath}" | $SED -r 's#/#\\/#g'
}
fix_issue()
{
  local name="${1}"
  local snap_root="${2}"
  local fn="${snap_root}/etc/issue"
  local text_old="$(current_issue "${fn}")"
  local text_suffix=" --- snapshot ${name}"
  [ -f "${fn}" ] || return
  sedcmd="$SED -r 's/^(${text_old})(\\s+\\S+\\s+snapshot\\s+\\S+)*(.*)\$/\\1${text_suffix}\\3/g' --in-place"
  eval "$sedcmd" "'${fn}'"
  fn="${fn}.net" # change issue.net as well
  if [ -f "${fn}" ];
  then
    eval "$sedcmd" "'${fn}'"
  fi
}
fix_fstab()
{
  local snap_path="$(sed_escape_path "${1}")"
  local subvolume="${2}"
  local snap_root="${3}"
  if $ECHO $subvolume | grep -q "^${snap_path}"; then
    # abort on subvolumes of the snapshot series just created, for testing basically
    return
  fi
  local fstabpath="${snap_root}/etc/fstab"
  [ -f "$fstabpath" ] || return
  local chksum=$($CHKSUM "$fstabpath" | awk '{print $1}')
  # change all subvol= because we want to snap on all devices
  $SED -r "s/subvol=${subvolume}(\s)/subvol=${snap_path}\/${subvolume}\1/g" \
        --in-place "${snap_root}/etc/fstab"
  if [ "$($CHKSUM "$fstabpath" | awk '{print $1}')" != "$chksum" ]; then
    $ECHO "Fixed fstab for '$subvolume'"
  fi
  # http://stackoverflow.com/a/11958566
  # "/subvol=${subvolume}[,[:space:]]/ s/subvol=${subvolume}/subvol=${snap_path}\/${subvolume}/g" \
}
grub_entry()
{
  local snap_name="${1}"
  local root_path="$(sed_escape_path "${2}")"
  local boot_path="$(sed_escape_path "${3}")"
  # grab the main entry of grub.cfg in /boot and modify it to our needs
  # pay attention to not get previously generated entries containing @ or _
  $GREP -aozP '(?s)menuentry[^{]+gnulinux-simple[^{@_]+{[^}]+}' "${GRUBCFG}" \
    | $SED -r "s/'(\\w+)'/'\\1 [${snap_name}]'/" \
    | $SED -r "s/(gnulinux-simple-[^']+)/\\1-${snap_name}/" \
    | $SED -r "s/\\/vmlinuz/${boot_path}\\/vmlinuz/" \
    | $SED -r "s/\\/initrd/${boot_path}\\/initrd/" \
    | $SED -r "s/rootflags=subvol=[^\\s]+\\s/rootflags=subvol=${root_path} /"
}

fix_grub()
{
  local btrfs_root="${1}"
  tempfn="$(mktemp)"
  head -n 6 "${GRUBCTM}" > "${tempfn}"
  $ECHO -e "# boot menu group for existing snapshots," \
           "\n# created by '${this_script}'" >> "${tempfn}"
  $ECHO -e "submenu 'Snapshots' \$menuentry_id_option " \
           "'gnulinux-snapshots-96549620-14b1-4096-bd2b-0c9cf72cfadb' {" \
           >> "${tempfn}"
  # scan for existing snapshots
  for subvolume in $(get_subvolumes "${btrfs_root}" noparent)
  do
    local snap_name="$(dirname "${subvolume}")"
    local root_path="/${subvolume}"
    # process root subvolumes only
    if [ "x${snap_name}/${root_volume_name}x" != "x${subvolume}x" ]; then
      continue
    fi;
    grub_entry "${snap_name}" "${root_path}" >> "${tempfn}"
  done
  $ECHO "}" >> "${tempfn}"
  cat "${tempfn}" > "${GRUBCTM}"
  rm "${tempfn}"
  $UPDATE_GRUB
}
# if xmessage -center -default yes -buttons yes:0,no:1 sdfdsafdsafsd; then echo true; else echo false; fi

# remove existing snapshots
remove_old_snaps()
{
  local btrfs_root="${1}"
  local ts_remove="${2}"
  if [ -z "$ts_remove" ]; then
    local timestamp_ref="$(format_timestamp ${time_delta_secs})"
    # get a list of time stamps to be removed:
    # get a sorted list of unique time stamps, newest last,
    # skip the newest $count_to_keep
    # get those older as the reference time stamp $timestamp_ref
    local ts_remove="$(find_old_snaps "${btrfs_root}" \
      | $AWK '{print $1}' | $UNIQ | $SORT | head -n -"$count_to_keep" \
      | $AWK -v ref="$timestamp_ref" '{ if ($1 < ref) print $1 }')"
    [ -z "$ts_remove" ] && return
    $ECHO "Keeping snapshots of $btrfs_root up to $timestamp_ref,"\
          "at least $count_to_keep:"
  fi
  local IFS=$'
'
  for candidate in $(find_old_snaps "${btrfs_root}")
  do
    local ts="${candidate%% /*}"
    local path_to_snapshot="/${candidate#*/}"
    if ! $ECHO "$ts_remove" | $GREP -q "$ts"
    then
      $ECHO "  Keeping  [${ts}] '${path_to_snapshot}'"
      continue
    fi
    $ECHO "  Removing [${ts}] '${path_to_snapshot}'"
    $BTRFS subvolume delete -C "${path_to_snapshot}"
    rmdir --ignore-fail-on-non-empty "$(dirname ${path_to_snapshot})"
  done
}

get_timestamp()
{
  local path_to_snapshot="${1}"
  local ts_path="${path_to_snapshot}${timestamp_path}"
  if [ ! -f "${ts_path}" ]; then
    local ts_path=""
  fi
  $ECHO "$ts_path"
}

# get existing snapshots candidates for removal
find_old_snaps()
{
  local btrfs_root="${1}"
  for subvolume in $(get_subvolumes "${btrfs_root}" noparent) # scan
  do
    local path_to_snapshot="${btrfs_root}/${subvolume}"
    local snap_ts_path="$(get_timestamp "${path_to_snapshot}")"
    if [ ! -f "$snap_ts_path" ]; then
      continue # no stored timestamp found, skipped
    fi
    local ts="$(cat "${snap_ts_path}")"
    [ -z "$ts" ] && continue # timestamp empty
    $ECHO "$ts ${path_to_snapshot}"
  done
}

create_snapshot()
{
  local btrfs_root="${1}"
  local subvolumes="$(get_subvolumes "${btrfs_root}")"
  local IFS=$'
'
  for subvolume in $subvolumes
  do
    local path_to_subvol="${btrfs_root}/${subvolume}"
    if [ -f "$(get_timestamp "$path_to_subvol")" ]; then
      continue
    fi
    $ECHO "processing '$subvolume' ..."
    local snap_dir="${btrfs_root}/${path_to_snapshots}/$($DIRNAME ${subvolume})"
    $MKDIR -p "${snap_dir}"

    local snap_root="${btrfs_root}/${path_to_snapshots}/${subvolume}"
    $BTRFS subvolume snapshot "${path_to_subvol}" "${snap_root}"
    # add timestamp file to snapshot for removing outdated ones next time
    $ECHO "${timestamp}" > "${snap_root}${timestamp_path}"

    if [ "${subvolume}" != "${root_volume_name}" ]; then
      continue
    fi
    $ECHO "  => preparing root subvolumes for boot"

    fix_issue "${path_to_snapshots}" "${snap_root}"
    fix_grub "${btrfs_root}"

    for subvolumeX in $(sed_escape_path "$subvolumes")
    do
      fix_fstab "${path_to_snapshots}" "${subvolumeX}" "${snap_root}"
    done
  done
}

# get mount points from /etc/fstab which mount the
# root volume of the actually used 'subvol='
get_roots()
{
  # ignore comments, get btrfs fs type only,
  # get mount points starting with /run/btrfs-
  $GREP -Ev '^\s*#' /etc/fstab \
    | $GREP -E '\sbtrfs\s' \
    | $GREP -v 'subvol=' \
    | awk '{print $2}'
}

prepare_root()
{
  local btrfs_root="${1}"
  local btrfs_root="${btrfs_root%/}" # remove trailing / if any
  [ -d "${btrfs_root}" ] || $MKDIR "${btrfs_root}"
  $MOUNT "${btrfs_root}"
  $ECHO "${btrfs_root}"
}

close_root()
{
  local btrfs_root="${1}"
  $UMOUNT "${btrfs_root}"
  rmdir "${btrfs_root}"
}

create_snapshots()
{
  local timestamp="$(format_timestamp)"
  local snapshot_name="${1}"
  if [ -z "${snapshot_name}" ]; then
    snapshot_name="${timestamp}"
  else
    snapshot_name="${timestamp}_${snapshot_name}"
  fi
  local path_to_snapshots="@${snapshot_name}"
  for btrfs_root in $(get_roots);
  do
    local btrfs_root="$(prepare_root "${btrfs_root}")"
    remove_old_snaps "${btrfs_root}"
    create_snapshot "${btrfs_root}"
    continue
    close_root "${btrfs_root}"
  done
}

usage_make()
{
  $ECHO "This script accepts one optional parameter:"
  $ECHO "  A descriptive name which is appended to the timestamp"
  $ECHO "  to make up for an improved snapshot name."
  $ECHO "CAUTION: This script deletes outdated snapshots older"
  $ECHO "         than $days_to_keep days and updates the grub configuration"
  $ECHO "         in order to allow booting into each managed snapshot."
  exit 1
}

usage_remove()
{
  $ECHO "This script removes all snapshots with a given timestamp from the "
  $ECHO "given btrfs root volume."
  $ECHO "usage: "
  $ECHO "  $script_name <btrfs root mount point> <YYYY-mm-dd_HHMMSS>"
  exit 1
}

main()
{
  script_name="$(basename "$this_script")"
  script_name="${script_name%*.sh}"
  echo "test: '$script_name'"
  case "$script_name" in
    makesnapshot)
      if ([ $# -gt 1 ] || [ "x$1" = "x--help" ] || [ "x$1" = "x-h" ]); then
        usage_make
      fi
      local snapshot_name="${1}" # ex.: 'state_at_last_successful_boot'
      create_snapshots "${snapshot_name}"
    ;;
    removesnapshot)
      if [ -z "${1}" ] || [ -z "${2}" ]; then
        usage_remove
      fi
      local btrfs_root="$(prepare_root "${1}")"
      local timestamp="${2}" # ex.: YYYY-mm-dd_HHMMSS
      remove_old_snaps "${btrfs_root}" "${timestamp}"
      #close_root "${btrfs_root}"
    ;;
  esac
}

main $@

$SYNC

# vim: set ts=2 sts=2 sw=2 tw=0:

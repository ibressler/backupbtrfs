#!/bin/sh
# makesnapshot.sh
# Creates btrfs snapshots of filesystems on multiple devices based on
# a common time stamp.
# Requires a mount point for the root of each file system being specified
# in /etc/fstab. It is mounted as needed.
# <example>
#
# originally from:
# https://wiki.archlinux.org/index.php/Btrfs_-_Tips_and_tricks
# modifed 2015-06, Ingo Bressler <dev@ingobressler.net>
#
# Works for the author on Ubuntu 14.04.
# USE WITH EXTREME CARE, DATA LOSS MAY OCCUR, NO WARRANTY!
# License: GPLv3
#
# example call:
# bash /usr/local/bin/snapshot_current_system_state.sh '/run/btrfs-root' '__current/ROOT' '__snapshot/__state_at_last_successful_boot' 

ECHO="/bin/echo"
BTRFS="/bin/btrfs"
AWK="/usr/bin/awk"
SED="/bin/sed --posix --regexp-extended"
SED2="/bin/sed --regexp-extended"
DIRNAME="/usr/bin/dirname"
DATE="/bin/date"
SYNC="/bin/sync"
MKDIR="/bin/mkdir"
GREP="/bin/grep"
MOUNT="/bin/mount"
UMOUNT="/bin/umount"
GRUBCFG="/boot/grub/grub.cfg" # source for menu entry pattern
GRUBCTM="/etc/grub.d/40_custom" # target for menu entries
# sys command for regenerating grub menu with contents of $GRUBCTM file
UPDATE_GRUB="/usr/sbin/update-grub"

#btrfs_root="${1}"          # example: '/run/btrfs-root'
#path_to_root_volume="${2}" # example: '__current/ROOT'
snapshot_name="${1}"       # example: 'state_at_last_successful_boot'
root_volume_name="@"
days_to_keep=30
time_delta_secs=$((${days_to_keep} * 24 * 3600))
time_delta_secs=7000 # for debugging
timestamp_path="/SNAPSHOT-TIMESTAMP"
this_script="${0}"

if ([ $# -gt 1 ] || [ "x$1" = "x--help" ] || [ "x$1" = "x-h" ])
then
  $ECHO "This script accepts one optional parameter:"
  $ECHO "  A descriptive name which is appended to the timestamp"
  $ECHO "  to make up for an improved snapshot name."
  $ECHO "CAUTION: This script deletes outdated snapshots older"
  $ECHO "         than $days_to_keep days and updates the grub configuration"
  $ECHO "         in order to allow booting into each managed snapshot."
  exit 0
fi

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

get_subvolumes()
{
  local btrfs_root="${1}"
  local invert=""
  [ "${2}" != "parent" ] && invert="-v"
  $ECHO -n "$(btrfs subvolume list -q "${btrfs_root}" | \
                $GREP ${invert} 'parent_uuid -' | \
                $AWK '{print $NF}')"
}
get_timestamp()
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
  $ECHO "${inpath}" | $SED 's/\//\\\//g'
}
fix_issue()
{
  local timestamp="${1}"
  local name="${2}"
  local snap_root="${3}"
  local fn="${snap_root}/etc/issue"
  local text_old="$(current_issue "${fn}")"
  local text_new="${text_old} --- snapshot ${name} [${timestamp}]"
  [ -f "${fn}" ] || return
  $SED "s/${text_old}/${text_new}/g" --in-place "${fn}"
  fn="${fn}.net" # change issue.net as well
  if [ -f "${fn}" ];
  then
    $SED "s/${text_old}/${text_new}/g" --in-place "${fn}"
  fi
}
fix_fstab()
{
  local snap_path="$(sed_escape_path "${1}")"
  local subvolume="${2}"
  local snap_root="${3}"
  $ECHO "fixing fstab for '$subvolume'"
  # change all subvol= because we want to snap on all devices
  $SED "s/subvol=${subvolume}/subvol=${snap_path}\/${subvolume}/g" \
        --in-place "${snap_root}/etc/fstab"
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
    | $SED2 "s/'(\w+)'/'\1 [${snap_name}]'/" \
    | $SED2 "s/(gnulinux-simple-[^']+)/\1-${snap_name}/" \
    | $SED2 "s/\/vmlinuz/${boot_path}\/vmlinuz/" \
    | $SED2 "s/\/initrd/${boot_path}\/initrd/" \
    | $SED2 "s/rootflags=subvol=[^\s]+\s/rootflags=subvol=${root_path} /"
}
# fix_grub "${path_to_snapshots}" "${subvolume}"
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
    grub_entry "${snap_name}" "${root_path}" >> "${tempfn}"
  done
  $ECHO "}" >> "${tempfn}"
  cat "${tempfn}" > "${GRUBCTM}"
  rm "${tempfn}"
  $UPDATE_GRUB
}
# if xmessage -center -default yes -buttons yes:0,no:1 sdfdsafdsafsd; then echo true; else echo false; fi

# remove existing snapshots, NOT YET
remove_old_snaps()
{
  local btrfs_root="${1}"
  local timestamp_ref="$(get_timestamp ${time_delta_secs})"
  $ECHO "Keeping snapshots of $btrfs_root up to $timestamp_ref"
  for subvolume in $(get_subvolumes "${btrfs_root}" noparent) # scan
  do
    local path_to_snapshot="${btrfs_root}/${subvolume}"
    [ -d "${path_to_snapshot}" ] || continue
    $ECHO -n "Testing for removal of '${path_to_snapshot}' ... "
    local snap_ts_path="${path_to_snapshot}${timestamp_path}"
    if [ ! -f "${snap_ts_path}" ]; then
      $ECHO "skipped."
      continue
    fi
    local ts="$(cat "${snap_ts_path}")"
    [ -z "$ts" ] && continue # not timestamp found
    if [ "${ts}" \> "${timestamp_ref}" ];
    then
      $ECHO "keep [${ts}]"
      continue
    fi
    $ECHO "remove [${ts}]"
    $BTRFS subvolume delete -C "${path_to_snapshot}"
    rmdir --ignore-fail-on-non-empty "$(dirname ${path_to_snapshot})"
  done
}

create_snapshot()
{
  local btrfs_root="${1}"
  local subvolumes="$(get_subvolumes "${btrfs_root}" parent)"
  for subvolume in $subvolumes
  do
    $ECHO "processing '$subvolume' ..."
    local snap_dir="${btrfs_root}/${path_to_snapshots}/$($DIRNAME ${subvolume})"
    $MKDIR -p "${snap_dir}"

    local snap_root="${btrfs_root}/${path_to_snapshots}/${subvolume}"
    $BTRFS subvolume snapshot \
      "${btrfs_root}/${subvolume}" "${snap_root}"
    # add timestamp file to snapshot for removing outdated ones next time
    $ECHO "${timestamp}" > "${snap_root}${timestamp_path}"

    if [ "${subvolume}" = "${root_volume_name}" ]
    then
      $ECHO "  => fixing root vol"

      fix_issue "${timestamp}" "${path_to_snapshots}" "${snap_root}"
      fix_grub "${btrfs_root}"

      for subvolumeX in $(sed_escape_path "$subvolumes")
      do
        fix_fstab "${path_to_snapshots}" "${subvolumeX}" "${snap_root}"
      done
    fi
  done
}

# get mount points from /etc/fstab which mount the
# root volume of the actually used 'subvol='
get_roots()
{
  $GREP -E '\sbtrfs\s' /etc/fstab | awk '{print $2}' | grep '^/run/btrfs-'
}

create_snapshots()
{
  local timestamp="$(get_timestamp)"
  local snapshot_name="${1}"
  if [ -z "${snapshot_name}" ]; then
    snapshot_name="${timestamp}"
  else
    snapshot_name="${timestamp}_${snapshot_name}"
  fi
  local path_to_snapshots="@${snapshot_name}"
  for btrfs_root in $(get_roots);
  do
    [ -d "${btrfs_root}" ] || $MKDIR "${btrfs_root}"
    $MOUNT "${btrfs_root}"
    remove_old_snaps "${btrfs_root}"
    create_snapshot "${btrfs_root}"
    $UMOUNT "${btrfs_root}"
    rmdir "${btrfs_root}"
  done
}

create_snapshots "${snapshot_name}"

$SYNC

# vim: set ts=2 sts=2 sw=2 tw=0:

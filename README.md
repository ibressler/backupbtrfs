# yufrul

Creates bootable, rolling snapshots of btrfs root filesystems on suspend/powerdown automatically

## Contents

1. [Requirements & Assumptions](#requirements--assumptions)
2. [Bootable Snapshots](#bootable-snapshots)
3. [Removing Outdated Snapshots](#removing-outdated-snapshots)
4. [Tested on](#tested-on)
5. [Inspired by](#inspired-by)
6. [License](#license)
7. [Naming](#naming)
8. [Contact](#contact)

## Requirements & Assumptions

Each invocation of `makesnapshot.sh` creates a new snapshot based on the same time stamp on all *monitored* filesystems.
*Monitored* filesystems are identified by `/run/btrfs-XYZ` mount-points in `/etc/fstab` (see below for an example).
If the mount-points does not exist they are created first as well as unmounted and removed after operation.

Furthermore, it is assumes that the active filesystem which should be taken a snapshot of is actually a subvolume.
For each snapshot there is a new directory on each top-level filesystem having the snapshot name.

Top-level structure:
```
/run/btrfs-root:
@
@2015-06-14_155234/@
@2015-06-14_164429/@
@2015-06-14_172805/@

/run/btrfs-home:
@home
@2015-06-14_155234/@home
@2015-06-14_164429/@home
@2015-06-14_172805/@home
```

## Bootable Snapshots

After creating a new snapshot by `btrfs subvolume snapshot` it is modified for convenience:

* A file `/SNAPSHOT-TIMESTAMP` containing the time stamp is created at the root of the snapshot.
* The issue file `/etc/issue` is adjusted on the root filesystem snapshot (assuming subvolume name *@*) to contain the original text appended with the snapshot name.
* The `/etc/fstab` file is adjusted to let the `subvol=@XYZ` parameter point to the appropriate snapshot.
* In order to be able to boot into a snapshot, a custom grub submenu in `/etc/grub.d/40_custom` is created. It contains the modified default menuentry copied from `/boot/grub/grub.cfg`. To put the changes into place, `update-grub` is run.

## Removing Outdated Snapshots

On successive runs of `makesnapshot.sh` it first removes outdated snapshots.
In order to accomplish this it extracts the time stamp of all existing snapshots and compares them
with a reference date, by default 30 days ago. If a snapshot is older it is removed by `btrfs subvolume delete`.

## Invoking on Suspend or Power-down

Enclosed is a script `onupdown.sh` which can be run automatically prior to entering suspend or powerdown state.
It opens up a message window to give the user a change to skip the snapshot creation and continues otherwise
by running `makesnapshot.sh` after a delay of 10 seconds.

The snapshot script is run in a xterm window to show the terminal output which is also written
to a log file `/var/log/snapshot.log` separately.
The operation finishes by closing the xterm window after another delay of 10 seconds.

It may work with any other `x-terminal-emulator` programs but adjusting the default font size
is rather simple with an xterm which should be available on many systems anyway (as long as there is X).

## Tested on

Works for the author on Ubuntu 14.04 with / and /home on different filesystems/devices and by mounting them via `subvol=@` and `subvol=@home` respectively.

Example `/etc/fstab`:
```
UUID=aa-bb-cc /               btrfs   defaults,<more opts>,subvol=@      0   1
UUID=aa-bb-cc /run/btrfs-root btrfs   defaults,<more opts>,noauto        0   1
UUID=cc-dd-ee /home           btrfs   defaults,<more opts>,subvol=@home  0   1
UUID=cc-dd-ee /run/btrfs-home btrfs   defaults,<more opts>,noauto        0   1
```

**USE WITH EXTREME CARE, DATA LOSS MAY OCCUR, NO WARRANTY!**

## Inspired by

https://wiki.archlinux.org/index.php/Btrfs_-_Tips_and_tricks

## License

GPLv3

## Naming

... purely arbitrarily by running `apg -m 5`

## Contact

Feel free to contact me for any comments, feedback or critics!


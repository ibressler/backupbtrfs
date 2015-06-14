# yufrul

Creates bootable, rolling snapshots of btrfs root filesystems on suspend/powerdown automatically

a common time stamp.
Requires a mount point for the root of each file system being specified
in /etc/fstab. It is mounted as needed.
<example>

# Tested on

Works for the author on Ubuntu 14.04 with / and /home on different filesystems/devices and by mounting them via `subvol=@` and `subvol=@home` respectively.

Example `/etc/fstab`:
```
UUID=aa-bb-cc /               btrfs   defaults,<more opts>,subvol=@      0   1
UUID=aa-bb-cc /run/btrfs-root btrfs   defaults,<more opts>,noauto        0   1
UUID=cc-dd-ee /home           btrfs   defaults,<more opts>,subvol=@home  0   1
UUID=cc-dd-ee /run/btrfs-home btrfs   defaults,<more opts>,noauto        0   1
```

USE WITH EXTREME CARE, DATA LOSS MAY OCCUR, NO WARRANTY!

# Inspired by

https://wiki.archlinux.org/index.php/Btrfs_-_Tips_and_tricks

# License

GPLv3

# Naming

purely arbitrarily by running `apg -m 5`


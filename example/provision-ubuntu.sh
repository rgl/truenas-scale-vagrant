#!/bin/bash
set -euxo pipefail

iscsi_portal="${1:-10.10.0.2}:3260"

# install iscsi tools.
# NB to manually mount the iscsi target use, e.g.:
#       apt-get install -y open-iscsi
#       echo 'InitiatorName=iqn.2020-01.test:rpijoy' >/etc/iscsi/initiatorname.iscsi
#       systemctl restart iscsid
#       iscsiadm --mode discovery --type sendtargets --portal 10.10.0.2:3260 # list the available targets (e.g. 10.10.0.2:3260,1 iqn.2005-10.org.freenas.ctl:ubuntu)
#       iscsiadm --mode node --targetname iqn.2005-10.org.freenas.ctl:ubuntu-data --login # start using the target.
#       find /etc/iscsi -type f # list the configuration files.
#       ls -lh /dev/disk/by-path/*-iscsi-iqn.* # list all iscsi block devices (e.g. /dev/disk/by-path/ip-10.10.0.2:3260-iscsi-iqn.2005-10.org.freenas.ctl:ubuntu-data-lun-0 -> ../../sdb)
#       mkfs.ext4 /dev/sdb
#       lsblk /dev/sdb # lsblk -O /dev/sdb
#       blkid /dev/sdb
#       mount -o noatime /dev/sdb /mnt
#       ls -laF /mnt
#       umount /mnt
#       iscsiadm --mode node --targetname iqn.2005-10.org.freenas.ctl:ubuntu-data --logout # stop using the target.
# see https://wiki.archlinux.org/index.php/Open-iSCSI
# see https://github.com/open-iscsi/open-iscsi
# see https://tools.ietf.org/html/rfc7143
apt-get install -y open-iscsi

# mount the ubuntu-data iscsi disk lun.
iscsiadm --mode discovery --type sendtargets --portal $iscsi_portal
iscsiadm --mode node --targetname iqn.2005-10.org.freenas.ctl:ubuntu-data --login
device="/dev/disk/by-path/ip-$iscsi_portal-iscsi-iqn.2005-10.org.freenas.ctl:ubuntu-data-lun-0"
while ! readlink $device 2>/dev/null 1>&2; do sleep 1; done
if ! blkid $device 2>/dev/null 1>&2; then
    mkfs.ext4 $device
fi
install -d /mnt/ubuntu-data
mount $device /mnt/ubuntu-data

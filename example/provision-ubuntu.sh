#!/bin/bash
set -euxo pipefail

storage_ip_address="${1:-10.10.0.3}"
iscsi_portal="${2:-10.10.0.2}:3260"
storage_mtu="${3:-9000}"
interfaces=($(ip link | perl -ne '/\d+: (e[nt].+?): / && print "$1\n"'))
lan_interface="${interfaces[0]}"
storage_interface="${interfaces[1]}"

# configure the storage network interface when running in vsphere.
dmi_sys_vendor=$(cat /sys/devices/virtual/dmi/id/sys_vendor)
if [ "$dmi_sys_vendor" == 'VMware, Inc.' ]; then
  cat >/etc/netplan/02-vmware.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $storage_interface:
      addresses:
        - $storage_ip_address/24
      mtu: $storage_mtu
EOF
  netplan apply
fi

# update the package cache.
apt-get update

# install vim.
apt-get install -y --no-install-recommends vim
cat >/etc/vim/vimrc.local <<'EOF'
syntax on
set background=dark
set esckeys
set ruler
set laststatus=2
set nobackup
EOF

# configure the shell.
cat >/etc/profile.d/login.sh <<'EOF'
[[ "$-" != *i* ]] && return
export EDITOR=vim
export PAGER=less
alias l='ls -lF --color'
alias ll='l -a'
alias h='history 25'
alias j='jobs -l'
EOF
cat >/etc/inputrc <<'EOF'
set input-meta on
set output-meta on
set show-all-if-ambiguous on
set completion-ignore-case on
"\e[A": history-search-backward
"\e[B": history-search-forward
"\eOD": backward-word
"\eOC": forward-word
EOF

# add support for bash completions.
apt-get install -y bash-completion

# install iptables.
apt-get install -y iptables

# install tcpdump.
apt-get install -y tcpdump

# install iscsi tools.
# NB to manually mount the iscsi target use, e.g.:
#       apt-get install -y open-iscsi
#       echo 'InitiatorName=iqn.2020-01.test:rpijoy' >/etc/iscsi/initiatorname.iscsi
#       systemctl restart iscsid
#       iscsiadm --mode discovery --type sendtargets --portal 10.10.0.2:3260 # list the available targets (e.g. 10.10.0.2:3260,1 iqn.2005-10.org.freenas.ctl:ubuntu)
#       iscsiadm --mode node --targetname iqn.2005-10.org.freenas.ctl:ubuntu --login # start using the target.
#       find /etc/iscsi -type f # list the configuration files.
#       ls -lh /dev/disk/by-path/*-iscsi-iqn.* # list all iscsi block devices (e.g. /dev/disk/by-path/ip-10.10.0.2:3260-iscsi-iqn.2005-10.org.freenas.ctl:ubuntu-lun-0 -> ../../sdb)
#       mkfs.ext4 /dev/sdb
#       lsblk /dev/sdb # lsblk -O /dev/sdb
#       blkid /dev/sdb
#       mount -o noatime /dev/sdb /mnt
#       ls -laF /mnt
#       umount /mnt
#       iscsiadm --mode node --targetname iqn.2005-10.org.freenas.ctl:ubuntu --logout # stop using the target.
# see https://wiki.archlinux.org/index.php/Open-iSCSI
# see https://github.com/open-iscsi/open-iscsi
# see https://tools.ietf.org/html/rfc7143
apt-get install -y open-iscsi

# mount the ubuntu-data iscsi disk lun.
iscsiadm --mode discovery --type sendtargets --portal $iscsi_portal
iscsiadm --mode node --targetname iqn.2005-10.org.freenas.ctl:ubuntu --login
device="/dev/disk/by-path/ip-$iscsi_portal-iscsi-iqn.2005-10.org.freenas.ctl:ubuntu-lun-1"
while ! readlink $device 2>/dev/null 1>&2; do sleep 1; done
if ! blkid $device 2>/dev/null 1>&2; then
    mkfs.ext4 $device
fi
install -d /mnt/ubuntu-data
mount $device /mnt/ubuntu-data

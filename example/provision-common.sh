#!/bin/bash
set -euxo pipefail

storage_ip_address="${1:-10.10.0.3}"
storage_mtu="${2:-9000}"
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

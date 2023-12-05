#!/bin/bash
set -euxo pipefail

ip_address="${1:-10.10.0.3}"
iscsi_portal_ip_address="${2:-10.10.0.2}"
mtu="${3:-9000}"
dhcp_range="${4:-10.10.0.100,10.10.0.200,10m}"
dns_domain="$(hostname --domain)"
interfaces=($(ip link | perl -ne '/\d+: (e[nt].+?): / && print "$1\n"'))
lan_interface="${interfaces[0]}"
storage_interface="${interfaces[1]}"


#
# mount the windows-pe iso.

install -d /var/pixie/windows-pe-iso
if [ -e /vagrant/tmp/windows-pe-vagrant/winpe-amd64.iso ]; then
  iso_path='/vagrant/tmp/windows-pe-vagrant/winpe-amd64.iso'
else
  iso_url='https://github.com/rgl/windows-pe-vagrant/releases/download/v20230409/windows-pe-20230409-amd64.iso'
  iso_path="/vagrant/$(basename "$iso_url")"
  if [ ! -e "$iso_path" ]; then
    wget -qO "$iso_path" "$iso_url"
  fi
fi
echo "$iso_path /var/pixie/windows-pe-iso udf ro 0 0" >>/etc/fstab
mount -a


#
# get wimboot.
# see http://ipxe.org/wimboot

wimboot_url='https://github.com/ipxe/wimboot/releases/download/v2.7.6/wimboot'
wimboot_sha='111a6d1cc6a2a2f7b458d81efeb9c5b3f93f7751a0e79371c049555bb474fc85'
wimboot_path='/var/pixie/wimboot'
install -d "$(dirname "$wimboot_path")"
wget -qO "$wimboot_path" "$wimboot_url"
if [ "$(sha256sum "$wimboot_path" | awk '{print $1}')" != "$wimboot_sha" ]; then
  echo "downloaded $wimboot_url failed the checksum verification"
  exit 1
fi


#
# provision the pixie assets.

install -d /var/pixie
cat >/var/pixie/boot.ipxe <<EOF
#!ipxe
chain --autofree --replace boot-\${mac:hexraw}.ipxe
EOF
# set the debian-live-boot machine boot script.
cat >/var/pixie/boot-080027000020.ipxe <<EOF
#!ipxe
set initiator-iqn iqn.2010-04.org.ipxe:\${mac:hexraw}
set target_boot iscsi:$iscsi_portal_ip_address::::iqn.2005-10.org.freenas.ctl:debian-live-boot
echo iSCSI initiator:   \${initiator-iqn}
echo iSCSI target_boot: \${target_boot}
sanboot \${target_boot}
EOF
# set the ubuntu-boot machine boot script.
cat >/var/pixie/boot-080027000021.ipxe <<EOF
#!ipxe
set initiator-iqn iqn.2010-04.org.ipxe:\${mac:hexraw}
set target_boot iscsi:$iscsi_portal_ip_address::::iqn.2005-10.org.freenas.ctl:ubuntu-boot
echo iSCSI initiator:   \${initiator-iqn}
echo iSCSI target_boot: \${target_boot}
sanboot \${target_boot}
EOF
# set the opensuse-boot machine boot script.
cat >/var/pixie/boot-080027000022.ipxe <<EOF
#!ipxe
set initiator-iqn iqn.2010-04.org.ipxe:\${mac:hexraw}
set target_boot iscsi:$iscsi_portal_ip_address::::iqn.2005-10.org.freenas.ctl:opensuse-boot
echo iSCSI initiator:   \${initiator-iqn}
echo iSCSI target_boot: \${target_boot}
sanboot \${target_boot}
EOF
# set the windows-boot machine boot script.
cat >/var/pixie/boot-080027000023.ipxe <<EOF
#!ipxe
set initiator-iqn iqn.2010-04.org.ipxe:\${mac:hexraw}
set target_boot iscsi:$iscsi_portal_ip_address::::iqn.2005-10.org.freenas.ctl:windows-boot
echo iSCSI initiator:   \${initiator-iqn}
echo iSCSI target_boot: \${target_boot}
#sanboot \${target_boot}
# TODO why setting sanhook makes windows stay at the loading screen for about 2m?
sanhook \${target_boot}
kernel wimboot
initrd windows-pe-iso/Boot/BCD BCD
initrd windows-pe-iso/Boot/boot.sdi boot.sdi
initrd windows-pe-iso/sources/boot.wim boot.wim
boot
EOF


#
# provision the HTTP server.

apt-get install -y --no-install-recommends nginx
rm /etc/nginx/sites-enabled/default
cat >/etc/nginx/sites-available/pixie.conf <<EOF
server {
  listen $ip_address:80;
  root /var/pixie;
  autoindex on;
  access_log /var/log/nginx/boot.access.log;
}
EOF
ln -s ../sites-available/pixie.conf /etc/nginx/sites-enabled
systemctl restart nginx


#
# provision the DHCP/TFTP server.
# see http://www.thekelleys.org.uk/dnsmasq/docs/setup.html
# see http://www.thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html
# see https://wiki.archlinux.org/title/Dnsmasq
default_dns_resolver="$(resolvectl status $lan_interface | awk '/DNS Servers: /{print $3}')" # recurse queries through the default vagrant environment DNS server.
apt-get install -y --no-install-recommends dnsmasq
cat >/etc/dnsmasq.d/local.conf <<EOF
# NB DHCP leases are stored at /var/lib/misc/dnsmasq.leases

# verbose
log-dhcp
log-queries

# ignore host settings
no-resolv
no-hosts

# DNS server
#server=/$dns_domain/127.0.0.2 # forward the $dns_domain zone to the local pdns server.
server=$default_dns_resolver

# listen on specific interfaces
bind-interfaces

# TFTP
enable-tftp
tftp-root=/var/pixie

# UEFI HTTP (e.g. X86J4105/RPI4)
dhcp-match=set:efi64-http,option:client-arch,16 # x64 UEFI HTTP (16)
dhcp-option-force=tag:efi64-http,60,HTTPClient
dhcp-boot=tag:efi64-http,tag:eth1,http://$ip_address/ipxe.efi
dhcp-match=set:efiarm64-http,option:client-arch,19 # ARM64 UEFI HTTP (19)
dhcp-option-force=tag:efiarm64-http,60,HTTPClient
dhcp-boot=tag:efiarm64-http,tag:eth1,http://$ip_address/ipxe-arm64.efi

# BIOS/UEFI TFTP PXE (e.g. EliteDesk 800 G2)
# NB there's was a snafu between 7 and 9 in rfc4578 thas was latter fixed in
#    an errata.
#    see https://www.rfc-editor.org/rfc/rfc4578.txt
#    see https://www.rfc-editor.org/errata_search.php?rfc=4578
#    see https://www.iana.org/assignments/dhcpv6-parameters/dhcpv6-parameters.xhtml#processor-architecture
dhcp-match=set:bios,option:client-arch,0        # BIOS x86 (0)
dhcp-boot=tag:bios,undionly.kpxe
dhcp-match=set:efi32,option:client-arch,6       # EFI x86 (6)
dhcp-boot=tag:efi32,ipxe.efi
dhcp-match=set:efi64,option:client-arch,7       # EFI x64 (7)
dhcp-boot=tag:efi64,ipxe.efi
dhcp-match=set:efibc,option:client-arch,9       # EFI EBC (9)
dhcp-boot=tag:efibc,ipxe.efi
dhcp-match=set:efiarm64,option:client-arch,11   # EFI ARM64 (11)
dhcp-boot=tag:efiarm64,ipxe-arm64.efi

# iPXE HTTP (e.g. OVMF/RPI4)
dhcp-userclass=set:ipxe,iPXE
dhcp-boot=tag:ipxe,tag:bios,tag:eth1,http://$ip_address/boot.ipxe
dhcp-boot=tag:ipxe,tag:efi64,tag:eth1,http://$ip_address/boot.ipxe
dhcp-boot=tag:ipxe,tag:efiarm64,tag:eth1,http://$ip_address/boot.ipxe

# DHCP.
interface=eth1
#dhcp-option=option:ntp-server,$ip_address
# TODO why returning the mtu borks ipxe?
#dhcp-option=tag:eth1,option:mtu,$mtu
dhcp-option=tag:eth1,option:router # do not send the router/gateway option.
dhcp-range=tag:eth1,$dhcp_range
dhcp-ignore=tag:!known # ignore hosts that do not match a dhcp-host line.

# machines.
# TODO get mac and ip from variable.
dhcp-host=08:00:27:00:00:20,10.10.0.20,debian-live-boot
dhcp-host=08:00:27:00:00:21,10.10.0.21,ubuntu-boot
dhcp-host=08:00:27:00:00:22,10.10.0.22,opensuse-boot
dhcp-host=08:00:27:00:00:23,10.10.0.23,windows-boot
EOF
systemctl restart dnsmasq

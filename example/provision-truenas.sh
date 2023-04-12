#!/bin/bash
set -euxo pipefail

ip_address="${1:-10.10.0.2}"
mtu="${2:-9000}"

KiB=$((1024))
MiB=$((1024*KiB))
GiB=$((1024*MiB))

function mround {
    echo $((($1+$2-1)/$2*$2))
}

function api {
    # see http://10.10.0.2/api/docs/#restful
    # NB to use an api key, replace --user, --password and --auth-no-challenge,
    #    with --header, e.g.:
    #       wget -qO- --header "Authorization: Bearer $api_key" "$@"
    wget -qO- --user root --password root --auth-no-challenge "$@"
}

# create an local zfs volume and share it as an smb volume.
function create-smb-volume {
    local name="$1"
    # create the zfs volume.
    cli --command "storage dataset create name=\"tank/$name\" type=FILESYSTEM"
    zfs get all "tank/$name"
    # share the zfs volume.
    # see cli --command 'sharing smb query'
    cli --command "sharing smb create name=\"$name\" path=\"/mnt/tank/$name\" purpose=READ_ONLY ro=true"
}

# create an local zfs volume and share it as an iscsi volume at lun 0.
function create-volume {
    local name="$1"
    local volsize="$(mround $2 $((16*1024)))"
    local volblocksize='16K' # NB for some odd readon, this is not a decimal like volsize (or both are not strings).
    local shareblocksize="${3:-512}" # NB iPXE/BIOS/int13 can only read 512-byte blocks.
    local ro="${4:-false}"
    local portal_id="$(cli --mode csv --command 'sharing iscsi portal query' | perl -ne '/^(\d+),\d+,storage,/ && print $1')"
    local initiator_id="$(api "http://$ip_address/api/v2.0/iscsi/initiator" | jq -r '.[] | select(.comment=="storage") | .id')"
    # create the zfs volume.
    cli --command "storage dataset create name=\"tank/$name\" type=VOLUME volsize=$volsize volblocksize=\"$volblocksize\""
    zfs get all "tank/$name"
    # share the zfs volume.
    # see iscsi_target_create in the api docs.
    cli --command "sharing iscsi target create name=\"$name\" mode=ISCSI groups=[{\"portal\":$portal_id,\"initiator\":$initiator_id}] auth_networks=[\"$ip_address/24\"]"
    cli --command "sharing iscsi extent create name=\"$name\" type=DISK disk=\"zvol/tank/$name\" blocksize=$shareblocksize rpm=SSD ro=$ro"
    target_id="$(cli --mode csv --command 'sharing iscsi target query' | perl -ne "/^(\d+),$name,/ && print \$1")"
    extent_id="$(cli --mode csv --command 'sharing iscsi extent query' | perl -ne "/^(\d+),$name,/ && print \$1")"
    # TODO implement using the cli.
    # see iscsi_targetextent_create in the api docs.
    api \
        --header 'Content-Type:application/json' \
        --post-data "{\"target\":$target_id,\"lunid\":0,\"extent\":$extent_id}" \
        "http://$ip_address/api/v2.0/iscsi/targetextent"
}

function create-volume-from-path {
    local name="$1"
    local img_path="$2"
    local shareblocksize="${3:-512}" # NB iPXE/BIOS/int13 can only read 512-byte blocks.
    local ro="${4:-false}"
    volsize=$(qemu-img info "$img_path" | perl -ne '/^virtual size: .+ \((\d+) bytes\)/ && print $1')
    create-volume "$name" "$volsize" "$shareblocksize" "$ro"
    qemu-img convert -O raw "$img_path" "/dev/tank/$name"
    fdisk -l "/dev/tank/$name"
}

function create-volume-from-url {
    local name="$1"
    local img_url="$2"
    local shareblocksize="${3:-512}" # NB iPXE/BIOS/int13 can only read 512-byte blocks.
    local ro="${4:-false}"
    local img_path="$(basename "$img_url")"
    wget -qO "$img_path" "$img_url"
    create-volume-from-path "$name" "$img_path" "$shareblocksize" "$ro"
    rm "$img_path"
}


#
# wait for the system to be ready.

while [ "$(cli --command 'system state')" != 'READY' ]; do sleep 5; done


#
# configure the network.

# show the ip information before changes.
ip addr
ip route
cli --command 'network interface query'

# configure the network interfaces.
# see cli --command 'network interface man update'
interfaces=($(ip link | perl -ne '/\d+: (en.+?): / && print "$1\n"'))
lan_interface="${interfaces[0]}"
storage_interface="${interfaces[1]}"
cli --command "network interface update $lan_interface ipv4_dhcp=true ipv6_auto=false description=\"lan\""
cli --command "network interface update $storage_interface aliases=[\"$ip_address/24\"] ipv4_dhcp=false ipv6_auto=false mtu=$mtu description=\"storage\""
cli --command 'network interface commit' && cli --command 'network interface checkin'

# show the ip information after changes.
ip addr
ip route
cli --command 'network interface query'


#
# create users.

cli --command 'account user create uid=3000 username=vagrant password=vagrant full_name=vagrant group_create=true shell="/usr/sbin/nologin"'


#
# enable and start the cifs/samba/smb service.

cli --command 'service update id_or_name=cifs enable=true'
cli --command 'service start service=cifs'


#
# enable and start the iscsitarget service.

cli --command 'service update id_or_name=iscsitarget enable=true'
cli --command 'service start service=iscsitarget'


#
# configure the storage,

# create the iscsi storage portal.
cli --command "sharing iscsi portal create comment=storage listen=[{\"ip\":\"$ip_address\"}]"

# create the iscsi storage initiators group.
# TODO implement using the cli.
# see iscsi_initiator_create in the api docs.
api \
    --header 'Content-Type:application/json' \
    --post-data "{\"comment\":\"storage\",\"initiators\":[]}" \
    "http://$ip_address/api/v2.0/iscsi/initiator"

# create the tank pool with the sdb/sdc/sdd disks.
cli --command 'storage disk query'
pool_topology='{
    "data": [
        {"type": "RAIDZ1", "disks": ["sdb", "sdc", "sdd"]}
    ]
}'
cli --command "storage pool create name=tank topology=$pool_topology"
cli --mode csv --command 'storage pool query'

# create local zfs volumes and share them as smb volumes.
create-smb-volume sw
if [ -r /vagrant/windows-2022-amd64.iso ]; then
    cp /vagrant/windows-2022-amd64.iso /mnt/tank/sw/
fi
if [ -r /vagrant/virtio-win-0.1.229.iso ]; then
    cp /vagrant/virtio-win-0.1.229.iso /mnt/tank/sw/
fi

# create local zfs volumes and share them as iscsi volumes.
create-volume ubuntu-data $((1*GiB)) 4096
create-volume windows-data $((1*GiB)) 4096
if [ -r /vagrant/tmp/debian-live-builder-vagrant/live-image-amd64.hybrid.iso ]; then
    create-volume-from-path debian-live-boot /vagrant/tmp/debian-live-builder-vagrant/live-image-amd64.hybrid.iso 512 true
else
    create-volume-from-url debian-live-boot https://github.com/rgl/debian-live-builder-vagrant/releases/download/v20230407/debian-live-20230407-amd64.iso 512 true
fi
if [ -r /vagrant/tmp/debian-vagrant/box.img ]; then
    create-volume-from-path debian-boot /vagrant/tmp/debian-vagrant/box.img 512
fi
if [ -r /vagrant/tmp/ubuntu-vagrant/box.img ]; then
    create-volume-from-path ubuntu-boot /vagrant/tmp/ubuntu-vagrant/box.img 512
fi
create-volume opensuse-boot $((16*GiB)) 512
create-volume windows-boot $((32*GiB)) 512

# show zfs status.
zpool status -v

# show all datasets.
cli --mode csv --command 'storage dataset query'

#!/bin/bash
set -euxo pipefail

ip_address="${1:-10.10.0.2}"
mtu="${2:-9000}"


function api {
    # see http://10.10.0.2/api/docs/#restful
    # NB to use an api key, replace --user, --password and --auth-no-challenge,
    #    with --header, e.g.:
    #       wget -qO- --header "Authorization: Bearer $api_key" "$@"
    wget -qO- --user root --password root --auth-no-challenge "$@"
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
# configure the storage,

# create the tank pool with the sdb/sdc/sdd disks.
cli --command 'storage disk query'
pool_topology='{
    "data": [
        {"type": "RAIDZ1", "disks": ["sdb", "sdc", "sdd"]}
    ]
}'
cli --command "storage pool create name=tank topology=$pool_topology"
cli --mode csv --command 'storage pool query'

# define the zvol size.
KiB=$((1024))
MiB=$((1024*KiB))
GiB=$((1024*MiB))
volsize=$((10*GiB))
volblocksize='16K' # NB for some odd readon, this is not a decimal like volsize (or both are not strings).

# create the ubuntu-data zvol.
cli --command "storage dataset create name=\"tank/ubuntu-data\" type=VOLUME volsize=$volsize volblocksize=\"$volblocksize\""
zfs get all tank/ubuntu-data

# create the windows-data zvol.
cli --command "storage dataset create name=\"tank/windows-data\" type=VOLUME volsize=$volsize volblocksize=\"$volblocksize\""
zfs get all tank/windows-data

# show all datasets.
cli --mode csv --command 'storage dataset query'


#
# configure the shares.

# create the storage portal.
cli --command "sharing iscsi portal create comment=storage listen=[{\"ip\":\"$ip_address\"}]"
portal_id="$(cli --mode csv --command 'sharing iscsi portal query' | perl -ne '/^(\d+),\d+,storage,/ && print $1')"

# create the storage initiators group.
# TODO implement using the cli.
# see iscsi_initiator_create in the api docs.
api \
    --header 'Content-Type:application/json' \
    --post-data "{\"comment\":\"storage\",\"initiators\":[]}" \
    "http://$ip_address/api/v2.0/iscsi/initiator"
initiator_id="$(api "http://$ip_address/api/v2.0/iscsi/initiator" | jq -r '.[] | select(.comment=="storage") | .id')"

# share the ubuntu-data volume.
# see iscsi_target_create in the api docs.
cli --command "sharing iscsi target create name=\"ubuntu\" mode=ISCSI groups=[{\"portal\":$portal_id,\"initiator\":$initiator_id}] auth_networks=[\"$ip_address/24\"]"
cli --command 'sharing iscsi extent create name="ubuntu-data" type=DISK disk="zvol/tank/ubuntu-data" blocksize=4096 rpm=SSD'
target_id="$(cli --mode csv --command 'sharing iscsi target query' | perl -ne '/^(\d+),ubuntu,/ && print $1')"
extent_id="$(cli --mode csv --command 'sharing iscsi extent query' | perl -ne '/^(\d+),ubuntu-data,/ && print $1')"
# TODO implement using the cli.
# see iscsi_targetextent_create in the api docs.
api \
    --header 'Content-Type:application/json' \
    --post-data "{\"target\":$target_id,\"lunid\":1,\"extent\":$extent_id}" \
    "http://$ip_address/api/v2.0/iscsi/targetextent"

# share the windows-data volume.
# see iscsi_target_create in the api docs.
cli --command "sharing iscsi target create name=\"windows\" mode=ISCSI groups=[{\"portal\":$portal_id,\"initiator\":$initiator_id}] auth_networks=[\"$ip_address/24\"]"
cli --command 'sharing iscsi extent create name="windows-data" type=DISK disk="zvol/tank/windows-data" blocksize=4096 rpm=SSD'
target_id="$(cli --mode csv --command 'sharing iscsi target query' | perl -ne '/^(\d+),windows,/ && print $1')"
extent_id="$(cli --mode csv --command 'sharing iscsi extent query' | perl -ne '/^(\d+),windows-data,/ && print $1')"
# TODO implement using the cli.
# see iscsi_targetextent_create in the api docs.
api \
    --header 'Content-Type:application/json' \
    --post-data "{\"target\":$target_id,\"lunid\":1,\"extent\":$extent_id}" \
    "http://$ip_address/api/v2.0/iscsi/targetextent"

# enable and start the iscsitarget service.
cli --command 'service update id_or_name=iscsitarget enable=true'
cli --command 'service start service=iscsitarget'

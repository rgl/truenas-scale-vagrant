#!/bin/bash
set -euxo pipefail

ip_address="${1:-10.10.0.2}"


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
interfaces=( $(ip link | perl -ne '/\d+: (en.+?): / && print "$1\n"') )
lan_interface="${interfaces[0]}"
storage_interface="${interfaces[1]}"
cli --command "network interface update $lan_interface ipv4_dhcp=true ipv6_auto=false description=\"lan\""
cli --command "network interface update $storage_interface aliases=[\"$ip_address/24\"] ipv4_dhcp=false ipv6_auto=false mtu=9000 description=\"storage\""
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

#!/bin/bash
set -euxo pipefail

vm_uuid="$1"
interfaces="$2"
interfaces_count="$(echo "$interfaces" | jq -r '.[]' | wc -l)"

vm_interfaces="$(govc device.info --vm.uuid "$vm_uuid" -json 'ethernet-*' | jq -r '[.Devices[].Backing.DeviceName]')"
vm_interfaces_count="$(echo "$vm_interfaces" | jq -r '.[]' | wc -l)"

diff=$(( interfaces_count + 1 - vm_interfaces_count ))

for _ in $(seq 1 $diff); do
    govc vm.network.add \
        --vm.uuid "$vm_uuid" \
        -net "$VSPHERE_VLAN" \
        -net.adapter vmxnet3
done

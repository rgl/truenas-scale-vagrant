#!/bin/bash
set -euxo pipefail

vm_uuid="$1"
disk_name="$2"
disk_size_gb="$3"

vm_disks="$(govc vm.info --vm.uuid "$vm_uuid" -json | jq -r '.VirtualMachines[].Layout.Disk[].DiskFile[]')"
if [ "$(echo "$vm_disks" | grep -E "-$disk_name\\.vmdk\$" | wc -l)" == '0' ]; then
    echo "Adding the $disk_name disk..."
    # NB vm_disks will contain lines with something like:
    #       [datastore] esxi-vagrant-example/esxi-vagrant-example.vmdk
    vm_data_disk_datastore="$(echo "$vm_disks" | head -1 | awk '{print $1}' | tr -d '[]')"
    vm_data_disk_name="$(echo "$vm_disks" | head -1 | awk '{print $2}' | sed "s,\\.vmdk,-$disk_name.vmdk,")"
    govc vm.change \
        --vm.uuid "$vm_uuid" \
        -e disk.enableUUID=TRUE
    govc vm.disk.create \
        --vm.uuid "$vm_uuid" \
        "-ds=$vm_data_disk_datastore" \
        "-name=$vm_data_disk_name" \
        -size "${disk_size_gb}GB"
fi

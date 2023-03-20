SHELL=bash
.SHELLFLAGS=-euo pipefail -c

VERSION=22.12

help:
	@echo type make build-libvirt, make build-uefi-libvirt

build-libvirt: truenas-scale-${VERSION}-amd64-libvirt.box
build-uefi-libvirt: truenas-scale-${VERSION}-uefi-amd64-libvirt.box
build-vsphere: truenas-scale-${VERSION}-amd64-vsphere.box

truenas-scale-${VERSION}-amd64-libvirt.box: truenas-scale.pkr.hcl Vagrantfile.template
	rm -f $@
	PACKER_KEY_INTERVAL=10ms CHECKPOINT_DISABLE=1 PACKER_LOG=1 PACKER_LOG_PATH=$@.log PKR_VAR_vagrant_box=$@ \
		packer build -only=qemu.truenas-scale-amd64 -on-error=abort -timestamp-ui truenas-scale.pkr.hcl
	@./box-metadata.sh libvirt truenas-scale-${VERSION}-amd64 $@

truenas-scale-${VERSION}-uefi-amd64-libvirt.box: truenas-scale.pkr.hcl Vagrantfile-uefi.template
	rm -f $@
	PACKER_KEY_INTERVAL=10ms CHECKPOINT_DISABLE=1 PACKER_LOG=1 PACKER_LOG_PATH=$@.log PKR_VAR_vagrant_box=$@ \
		packer build -only=qemu.truenas-scale-uefi-amd64 -on-error=abort -timestamp-ui truenas-scale.pkr.hcl
	@./box-metadata.sh libvirt truenas-scale-${VERSION}-uefi-amd64 $@

truenas-scale-${VERSION}-amd64-vsphere.box: truenas-scale-vsphere.pkr.hcl Vagrantfile.template
	CHECKPOINT_DISABLE=1 PACKER_LOG=1 PACKER_LOG_PATH=$@.log PKR_VAR_version=${VERSION} \
		packer build -only=vsphere-iso.truenas-scale-amd64 -timestamp-ui truenas-scale-vsphere.pkr.hcl
	rm -rf $@ tmp/$@
	install -d tmp/$@
	echo '{"provider":"vsphere"}' >tmp/$@/metadata.json
	cp Vagrantfile.template tmp/$@/Vagrantfile
	tar cvf $@ -C tmp/$@ metadata.json Vagrantfile
	rm -rf tmp/$@
	@echo 'Add the Vagrant Box with:'
	@echo ''	
	@echo "vagrant box add -f truenas-scale-${VERSION}-amd64 $@"

.PHONY: help build-libvirt build-uefi-libvirt build-vsphere

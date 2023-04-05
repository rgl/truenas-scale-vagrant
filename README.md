# About

This builds a [TrueNAS SCALE](https://www.truenas.com/truenas-scale/) vagrant box.

This also includes an example environment with:

* TrueNAS SCALE server.
    * `tank` storage pool.
    * `tank/ubuntu-data` zvol dataset.
    * `tank/windows-data` zvol dataset.
    * `tank/k3s/v/pvc-` prefixed zvol datasets.
    * `ubuntu` iSCSI target share.
        * LUN 0: `tank/ubuntu-data` dataset.
    * `windows` iSCSI target share.
        * LUN 0: `tank/windows-data` dataset.
    * `csi-k3s-pvc-` prefixed iSCSI target shares.
        * LUN 0: `tank/k3s/v/pvc-` prefixed dataset for a Kubernetes PVC.
* Ubuntu client.
    * `ubuntu-data` iSCSI LUN 0 initialized and mounted at `/mnt/ubuntu-data`.
* Windows client.
    * `windows-data` iSCSI LUN 0 initialized and mounted at `D:`.
* Kubernetes client.
    * iSCSI LUN initialized and mounted for a Kubernetes Persistent Volume Claims (PVC).

# Usage

Add the following entries to your machine `hosts` file:

```
10.10.0.2 truenas.example.com
10.10.0.4 git.example.com
```

Depending on your hypervisor, build and install the base box and start the
example environment:

* [libvirt/kvm/linux](#libvirt-usage)
* [VMware vSphere](#vmware-vsphere-usage)

After the example environment is running, open the Web UI:

http://truenas.example.com

Use the Web API:

```bash
truenas_api_base_url='http://truenas.example.com/api/v2.0'
function api {
    # see http://truenas.example.com/api/docs/#restful
    # NB to use an api key, replace --user, --password and --auth-no-challenge,
    #    with --header, e.g.:
    #       wget -qO- --header "Authorization: Bearer $api_key" "$@"
    wget -qO- --user root --password root --auth-no-challenge "$truenas_api_base_url/$@"
}
api system/state | jq -r
api system/general | jq
api disk | jq
api pool | jq
api pool/dataset | jq
```

Access the gitea example kubernetes application (which uses iSCSI persistent
storage) and login with the `gitea` username and the `abracadabra` password:

http://git.example.com

## libvirt usage

Install [`packer`](https://github.com/hashicorp/packer), [`vagrant`](https://github.com/hashicorp/vagrant), [`vagrant-libvirt`](https://github.com/vagrant-libvirt/vagrant-libvirt), and [`libvirt`](https://github.com/libvirt/libvirt) (see the [rgl/my-ubuntu-ansible-playbooks repository](https://github.com/rgl/my-ubuntu-ansible-playbooks)).

Install the [Ubuntu 22.04 box](https://github.com/rgl/ubuntu-vagrant).

Install the [Windows 2022 box](https://github.com/rgl/windows-vagrant).

Build the box and add it to the local vagrant installation:

```bash
time make build-libvirt
vagrant box add -f truenas-scale-22.12-amd64 truenas-scale-22.12-amd64-libvirt.box.json
```

Start the example:

```bash
cd example
time vagrant up --provider=libvirt --no-destroy-on-error --no-tty
```

## VMware vSphere usage

Install [`govc`](https://github.com/vmware/govmomi) and [`vagrant-vsphere`](https://github.com/nsidc/vagrant-vsphere) (see the [rgl/my-ubuntu-ansible-playbooks repository](https://github.com/rgl/my-ubuntu-ansible-playbooks)).

Apply the [vagrant-vsphere plugin ip-wait patch](https://github.com/rgl/my-ubuntu-ansible-playbooks/blob/main/roles/vagrant/files/vagrant-vsphere-ip-wait.patch).

Install the [Ubuntu 22.04 box](https://github.com/rgl/ubuntu-vagrant).

Install the [Windows 2022 box](https://github.com/rgl/windows-vagrant).

Set your vSphere details, and test the connection to vSphere:

```bash
cat >secrets.sh <<EOF
export GOVC_INSECURE='1'
export GOVC_HOST='vsphere.local'
export GOVC_URL="https://$GOVC_HOST/sdk"
export GOVC_USERNAME='administrator@vsphere.local'
export GOVC_PASSWORD='password'
export GOVC_DATACENTER='Datacenter'
export GOVC_CLUSTER='Cluster'
export GOVC_DATASTORE='Datastore'
export VSPHERE_OS_ISO="[$GOVC_DATASTORE] iso/TrueNAS-SCALE-22.12.1.iso"
export VSPHERE_ESXI_HOST='esxi.local'
export VSPHERE_TEMPLATE_FOLDER='test/templates'
export VSPHERE_TEMPLATE_NAME="$VSPHERE_TEMPLATE_FOLDER/truenas-scale-22.12-amd64-vsphere"
export VSPHERE_UBUNTU_TEMPLATE_NAME="$VSPHERE_TEMPLATE_FOLDER/ubuntu-22.04-amd64-vsphere"
export VSPHERE_WINDOWS_TEMPLATE_NAME="$VSPHERE_TEMPLATE_FOLDER/windows-2022-amd64-vsphere"
export VSPHERE_VM_FOLDER='test'
export VSPHERE_VM_NAME='truenas-scale-22.12-vagrant-example'
export VSPHERE_UBUNTU_VM_NAME='ubuntu-22.04-vagrant-example'
export VSPHERE_K3S_VM_NAME='ubuntu-22.04-k3s-vagrant-example'
export VSPHERE_WINDOWS_VM_NAME='windows-2022-vagrant-example'
# NB ensure that the associated vSwitch can use an 9000 MTU or modify the
#    CONFIG_STORAGE_MTU variable value inside the Vagrantfile file to
#    1500.
export VSPHERE_VLAN='packer'
export VSPHERE_IP_WAIT_ADDRESS='0.0.0.0/0'
# set the credentials that the guest will use
# to connect to this host smb share.
# NB you should create a new local user named _vagrant_share
#    and use that one here instead of your user credentials.
# NB it would be nice for this user to have its credentials
#    automatically rotated, if you implement that feature,
#    let me known!
export VAGRANT_SMB_USERNAME='_vagrant_share'
export VAGRANT_SMB_PASSWORD=''
EOF
source secrets.sh
# see https://github.com/vmware/govmomi/blob/master/govc/USAGE.md
govc version
govc about
govc datacenter.info # list datacenters
govc find # find all managed objects
```

Download the TrueNAS SCALE ISO (you can find the full iso URL in the [truenas-scale.pkr.hcl](truenas-scale.pkr.hcl) file) and place it inside the datastore at the path defined by the `VSPHERE_OS_ISO` environment variable (its value will end-up in the `vsphere_iso_url` packer user variable that is defined inside the [packer template](truenas-scale-vsphere.pkr.hcl)).

Build the box and add it to the local vagrant installation:

```bash
source secrets.sh
time make build-vsphere
```

Start the example:

```bash
cd example
time vagrant up --provider=vsphere --no-destroy-on-error --no-tty
```

# Packer boot_steps

As TrueNAS SCALE does not have a documented way to be pre-seeded, this environment has to
answer all the installer questions through the packer `boot_steps` interface. This is
quite fragile, so be aware when you change anything. The following table describes the
current steps and corresponding answers.

| step                                          | boot_steps                                                    |
|----------------------------------------------:|---------------------------------------------------------------|
| select Start TrueNAS Scale Installation       | `<enter>`                                                     |
| wait for the boot to finish                   | `<wait1m>`                                                    |
| select 1 Install/Upgrade                      | `<enter><wait3s>`                                             |
| choose destination media                      | ` <enter><wait3s>`                                            |
| proceed with the installation                 | `<enter><wait3s>`                                             |
| select 2 Root user (not recommended)          | `2<enter><wait3s>`                                            |
| set the password                              | `root<tab><wait3s>`                                           |
| confirm the password                          | `root<enter><wait3s>`                                         |
| wait for the installation to finish           | `<wait5m>`                                                    |
| accept the installation finished prompt       | `<enter><wait3s>`                                             |
| select 3 Reboot System                        | `3<enter>`                                                    |
| wait for the reboot to finish                 | `<wait5m>`                                                    |
| select 6 Open TrueNAS CLI Shell               | `6<enter><wait3s>`                                            |
| enable root login                             | `service ssh update rootlogin=true<enter><wait3s>`            |
| automatically start the ssh service on boot   | `service update id_or_name=ssh enable=true<enter><wait3s>`    |
| start the ssh service                         | `service start service=ssh<enter><wait3s>q<wait3s>`           |
| exit the TrueNAS CLI Shell                    | `exit<enter><wait15s>`                                        |

# Reference

* [RFC7143: Internet Small Computer System Interface (iSCSI) Protocol](https://www.rfc-editor.org/rfc/rfc7143)
* [OpenZFS (Wikipedia)](https://en.wikipedia.org/wiki/OpenZFS)
* [OpenZFS (TrueNAS)](https://www.truenas.com/zfs/)
* [openzfs/zfs repository](https://github.com/openzfs/zfs)
* [Using the TrueNAS CLI Shell](https://www.truenas.com/docs/scale/scaletutorials/truenasclishell/)
* [midcli: TrueNAS SCALE CLI](https://github.com/truenas/midcli)
* [truenas-installer: TrueNAS SCALE Installer](https://github.com/truenas/truenas-installer/blob/TS-22.12.1/usr/sbin/truenas-install)
* [democratic-csi: TrueNAS SCALE Kubernetes CSI provider](https://github.com/democratic-csi/democratic-csi)

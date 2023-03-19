# About

This builds a [TrueNAS SCALE](https://www.truenas.com/truenas-scale/) vagrant box.

# Usage

Install `packer`, `vagrant`, and `libvirt` (see the [rgl/my-ubuntu-ansible-playbooks repository](https://github.com/rgl/my-ubuntu-ansible-playbooks)).

Build the box and add it to the local vagrant installation:

```bash
time make build-libvirt
vagrant box add -f truenas-scale-22.12-amd64 truenas-scale-22.12-amd64-libvirt.box.json
```

Start the example:

```bash
cd example
time vagrant up --provider=libvirt --no-destroy-on-error --no-tty truenas
```

Open the Web UI:

http://10.10.0.2

Use the Web API:

```bash
ip_address='10.10.0.2'
function api {
    # see http://10.10.0.2/api/docs/#restful
    # NB to use an api key, replace --user, --password and --auth-no-challenge,
    #    with --header, e.g.:
    #       wget -qO- --header "Authorization: Bearer $api_key" "$@"
    wget -qO- --user root --password root --auth-no-challenge "$@"
}
api http://$ip_address/api/v2.0/system/state | jq -r
api http://$ip_address/api/v2.0/system/general | jq
api http://$ip_address/api/v2.0/disk | jq
api http://$ip_address/api/v2.0/pool | jq
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

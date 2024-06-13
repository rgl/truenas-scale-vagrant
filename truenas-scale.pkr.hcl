variable "disk_size" {
  type    = string
  default = 16 * 1024
}

variable "iso_url" {
  type    = string
  default = "https://download.sys.truenas.net/TrueNAS-SCALE-Dragonfish/24.04.1.1/TrueNAS-SCALE-24.04.1.1.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:966cbd7c9e2cd04b7db388f9ea8c75c869cf22e9e1512554896e6f1b374ed121"
}

variable "vagrant_box" {
  type = string
}

locals {
  boot_steps = [
    ["<enter>", "select Start TrueNAS Scale Installation"],
    ["<wait1m>", "wait for the boot to finish"],
    ["<enter><wait3s>", "select 1 Install/Upgrade"],
    [" <enter><wait3s>", "choose destination media"],
    ["<enter><wait3s>", "proceed with the installation"],
    ["1<enter><wait3s>", "select 1 Administrative user (admin)"],
    ["admin<tab><wait3s>", "set the password"],
    ["admin<enter><wait3s>", "confirm the password"],
    var.disk_size >= 64 * 1024 ? ["N<wait3s>", "do not create swap partition on boot devices"] : null,
    ["<wait5m>", "wait for the installation to finish"],
    ["<enter><wait3s>", "accept the installation finished prompt"],
    ["3<enter>", "select 3 Reboot System"],
    ["<wait5m>", "wait for the reboot to finish"],
    ["6<enter><wait3s>", "select 6 Open TrueNAS CLI Shell"],
    ["account user update uid_or_username=admin sudo_commands_nopasswd=\"ALL\"<enter><wait3s>", "configure the admin sudo command"],
    ["service ssh update password_login_groups=[\"builtin_administrators\"]<enter><wait3s>", "set the ssh password authentication login groups"],
    ["service ssh update passwordauth=true<enter><wait3s>", "enable ssh password authentication"],
    ["service update id_or_name=ssh enable=true<enter><wait3s>", "automatically start the ssh service on boot"],
    ["service start service=ssh<enter><wait3s>q<wait3s>", "start the ssh service"],
    ["exit<enter><wait15s>", "exit the TrueNAS CLI Shell"],
  ]
}

source "qemu" "truenas-scale-amd64" {
  headless         = true
  accelerator      = "kvm"
  machine_type     = "q35"
  boot_wait        = "5s"
  boot_steps       = local.boot_steps
  shutdown_command = "sudo poweroff"
  disk_discard     = "unmap"
  disk_interface   = "virtio-scsi"
  disk_size        = var.disk_size
  format           = "qcow2"
  net_device       = "virtio-net"
  iso_checksum     = var.iso_checksum
  iso_url          = var.iso_url
  cpus             = 2
  memory           = 8 * 1024
  qemuargs = [
    ["-cpu", "host"],
    ["-bios", "/usr/share/ovmf/OVMF.fd"],
    ["-device", "virtio-vga"],
    ["-device", "virtio-scsi-pci,id=scsi0"],
    ["-device", "scsi-hd,bus=scsi0.0,drive=drive0"],
  ]
  ssh_username = "admin"
  ssh_password = "admin"
  ssh_timeout  = "60m"
}

build {
  sources = [
    "source.qemu.truenas-scale-amd64",
  ]

  provisioner "shell" {
    # NB packer will write the inline script to a .sh file inside the /tmp
    #    directoy, but that directory is mounted with the noxec flag, so,
    #    we have to use another directory with exec permissions.
    remote_folder = "/dev/shm"
    inline = [
      "cat /etc/os-release",
    ]
  }

  post-processor "vagrant" {
    output               = var.vagrant_box
    vagrantfile_template = "Vagrantfile.template"
  }
}

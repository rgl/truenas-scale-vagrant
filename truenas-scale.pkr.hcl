variable "disk_size" {
  type    = string
  default = 16 * 1024
}

variable "iso_url" {
  type    = string
  default = "https://download.truenas.com/TrueNAS-SCALE-Bluefin/22.12.2/TrueNAS-SCALE-22.12.2.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:73a86e1ea163d5cd70dd2133b70fdea47ed7bba1a39c8d489110c8d8949562cf"
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
    ["2<enter><wait3s>", "select 2 Root user (not recommended)"],
    ["root<tab><wait3s>", "set the password"],
    ["root<enter><wait3s>", "confirm the password"],
    ["<wait5m>", "wait for the installation to finish"],
    ["<enter><wait3s>", "accept the installation finished prompt"],
    ["3<enter>", "select 3 Reboot System"],
    ["<wait5m>", "wait for the reboot to finish"],
    ["6<enter><wait3s>", "select 6 Open TrueNAS CLI Shell"],
    ["service ssh update rootlogin=true<enter><wait3s>", "enable root login"],
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
  shutdown_command = "poweroff"
  disk_cache       = "unsafe"
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
  ]
  ssh_username = "root"
  ssh_password = "root"
  ssh_timeout  = "60m"
}

source "qemu" "truenas-scale-uefi-amd64" {
  headless         = true
  accelerator      = "kvm"
  machine_type     = "q35"
  boot_wait        = "5s"
  boot_steps       = local.boot_steps
  shutdown_command = "poweroff"
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
  ssh_username = "root"
  ssh_password = "root"
  ssh_timeout  = "60m"
}

build {
  sources = [
    "source.qemu.truenas-scale-amd64",
    "source.qemu.truenas-scale-uefi-amd64",
  ]

  provisioner "shell" {
    inline = [
      "cat /etc/os-release",
    ]
  }

  post-processor "vagrant" {
    only = [
      "qemu.truenas-scale-amd64",
    ]
    output               = var.vagrant_box
    vagrantfile_template = "Vagrantfile.template"
  }

  post-processor "vagrant" {
    only = [
      "qemu.truenas-scale-uefi-amd64",
    ]
    output               = var.vagrant_box
    vagrantfile_template = "Vagrantfile-uefi.template"
  }
}

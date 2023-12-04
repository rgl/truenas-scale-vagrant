variable "disk_size" {
  type    = string
  default = 16 * 1024
}

variable "version" {
  type = string
}

variable "vsphere_host" {
  type    = string
  default = env("GOVC_HOST")
}

variable "vsphere_username" {
  type    = string
  default = env("GOVC_USERNAME")
}

variable "vsphere_password" {
  type      = string
  default   = env("GOVC_PASSWORD")
  sensitive = true
}

variable "vsphere_esxi_host" {
  type    = string
  default = env("VSPHERE_ESXI_HOST")
}

variable "vsphere_datacenter" {
  type    = string
  default = env("GOVC_DATACENTER")
}

variable "vsphere_cluster" {
  type    = string
  default = env("GOVC_CLUSTER")
}

variable "vsphere_datastore" {
  type    = string
  default = env("GOVC_DATASTORE")
}

variable "vsphere_folder" {
  type    = string
  default = env("VSPHERE_TEMPLATE_FOLDER")
}

variable "vsphere_network" {
  type    = string
  default = env("VSPHERE_VLAN")
}

variable "vsphere_ip_wait_address" {
  type        = string
  default     = env("VSPHERE_IP_WAIT_ADDRESS")
  description = "IP CIDR which guests will use to reach the host. see https://github.com/hashicorp/packer/blob/ff5b55b560095ca88421d3f1ad8b8a66646b7ab6/builder/vsphere/common/step_http_ip_discover.go#L32"
}

variable "vsphere_os_iso" {
  type    = string
  default = env("VSPHERE_OS_ISO")
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
    ["service ssh update adminlogin=true<enter><wait3s>", "enable ssh admin login"],
    ["service ssh update passwordauth=true<enter><wait3s>", "enable ssh password authentication"],
    ["service update id_or_name=ssh enable=true<enter><wait3s>", "automatically start the ssh service on boot"],
    ["service start service=ssh<enter><wait3s>q<wait3s>", "start the ssh service"],
    ["exit<enter><wait15s>", "exit the TrueNAS CLI Shell"],
  ]
  boot_command = flatten([for step in local.boot_steps : [step[0]]])
}

source "vsphere-iso" "truenas-scale-amd64" {
  firmware            = "efi"
  CPUs                = 2
  RAM                 = 8 * 1024
  boot_wait           = "5s"
  boot_command        = local.boot_command
  shutdown_command    = "sudo poweroff"
  convert_to_template = true
  insecure_connection = true
  vcenter_server      = var.vsphere_host
  username            = var.vsphere_username
  password            = var.vsphere_password
  vm_name             = "truenas-scale-${var.version}-amd64-vsphere"
  datacenter          = var.vsphere_datacenter
  cluster             = var.vsphere_cluster
  host                = var.vsphere_esxi_host
  folder              = var.vsphere_folder
  datastore           = var.vsphere_datastore
  guest_os_type       = "debian9_64Guest"
  ip_wait_address     = var.vsphere_ip_wait_address
  iso_paths = [
    var.vsphere_os_iso
  ]
  network_adapters {
    network      = var.vsphere_network
    network_card = "vmxnet3"
  }
  storage {
    disk_size             = var.disk_size
    disk_thin_provisioned = true
  }
  disk_controller_type = ["pvscsi"]
  ssh_password         = "admin"
  ssh_username         = "admin"
  ssh_timeout          = "60m"
}

build {
  sources = ["source.vsphere-iso.truenas-scale-amd64"]

  provisioner "shell" {
    inline = [
      "cat /etc/os-release",
    ]
  }
}

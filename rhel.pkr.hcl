packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.0.0"
    }
  }
}

variable "kernel_params" {
  type = string
}

variable "ssh_username" {
  type    = string
  default = "frqadmin"
}

variable "ssh_password" {
  type      = string
  sensitive = true
}

variable "output_dir" {
  type    = string
  default = "/var/lib/jenkins/packer-output"
}

variable "image_name" {
  type    = string
  default = "rhel-golden.qcow2"
}

# ============================================================================
# PHASE 1: Install the OS using the exploded kernel. No SSH communicator.
# ============================================================================
source "qemu" "rhel_install" {
  vm_name          = var.image_name
  output_directory = var.output_dir
  qemu_binary      = "/usr/libexec/qemu-kvm"

  iso_url      = "file:///tmp/vmlinuz"
  iso_checksum = "none"

  qemuargs = [
    ["-cpu", "host"],
    ["-kernel", "/tmp/vmlinuz"],
    ["-initrd", "/tmp/initrd.img"],
    ["-append", "${var.kernel_params} console=ttyS0 inst.reboot=0"],
    ["-serial", "stdio"]
  ]

  disk_size      = "100G"
  disk_interface = "virtio"
  format         = "qcow2"

  cpus     = 2
  memory   = 4096
  headless = true

  machine_type      = "q35"
  efi_boot          = true
  efi_firmware_code = "/usr/share/edk2/ovmf/OVMF_CODE.fd"
  efi_firmware_vars = "/usr/share/edk2/ovmf/OVMF_VARS.fd"

  net_device   = "virtio-net"
  communicator = "none"
}

# ============================================================================
# PHASE 2: Boot the freshly installed disk image to execute provisioners
# ============================================================================
source "qemu" "rhel_provision" {
  vm_name          = var.image_name
  output_directory = var.output_dir
  qemu_binary      = "/usr/libexec/qemu-kvm"

  disk_image       = true
  iso_url          = "${var.output_dir}/${var.image_name}"
  iso_checksum     = "none"

  qemuargs = [
    ["-cpu", "host"],
    ["-serial", "stdio"]
  ]

  cpus     = 2
  memory   = 4096
  headless = true

  machine_type      = "q35"
  efi_boot          = true
  efi_firmware_code = "/usr/share/edk2/ovmf/OVMF_CODE.fd"
  efi_firmware_vars = "/usr/share/edk2/ovmf/OVMF_VARS.fd"

  net_device   = "virtio-net"
  communicator = "ssh"
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "15m"

  shutdown_command = "sudo poweroff"
}

# ============================================================================
# Execution Flow (Split into 2 sequential steps)
# ============================================================================

# Step 1: Run the installer and wait for the VM to power off
build {
  sources = ["source.qemu.rhel_install"]
}

# Step 2: Now boot the disk, SSH in, and run provisioners
build {
  sources = ["source.qemu.rhel_provision"]

  provisioner "shell" {
    inline = [
      "sudo rm -f /etc/machine-id",
      "sudo systemd-machine-id-setup",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "sudo rm -f /var/lib/NetworkManager/dhclient-*.lease",
      "sudo rm -f /etc/udev/rules.d/70-persistent-net.rules",
      "sudo cloud-init clean || true"
    ]
  }

  post-processor "shell-local" {
    inline = ["echo 'Golden image ready: ${var.output_dir}/${var.image_name}'"]
  }
}
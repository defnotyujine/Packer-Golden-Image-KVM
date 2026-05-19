packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.0.0"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = ">= 1.0.0"
    }
  }
}

variable "kernel_url" {
  type = string
}

variable "initrd_url" {
  type = string
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

variable "ansible_dir" {
  type = string
}

variable "ansible_tags" {
  type    = string
  default = ""
}

variable "vault_pass_file" {
  type = string
}

source "qemu" "rhel" {
  vm_name          = var.image_name
  output_directory = var.output_dir
  qemu_binary      = "/usr/libexec/qemu-kvm"

  iso_url      = "file:///dev/null"
  iso_checksum = "none"

  qemuargs = [
    ["-cpu", "host"],
    ["-kernel", var.kernel_url],
    ["-initrd", var.initrd_url],
    ["-append", "${var.kernel_params} console=ttyS0"],
    ["-serial", "stdio"],
    ["-boot", "order=c,menu=off"]
  ]

  disk_size      = "100G"
  disk_interface = "virtio"
  format         = "qcow2"

  cpus     = 2
  memory   = 4096
  headless = true

  machine_type = "q35"
  efi_boot     = false

  net_device   = "virtio-net"
  communicator = "ssh"
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "60m"

  shutdown_command = "sudo poweroff"
}

build {
  sources = ["source.qemu.rhel"]

  provisioner "ansible" {
    playbook_file = "${var.ansible_dir}/playbooks/main_playbook.yml"
    sftp_command  = "/usr/libexec/openssh/sftp-server -e"

    extra_arguments = concat(
      [
        "--vault-password-file", var.vault_pass_file,
        "--ssh-extra-args", "-o StrictHostKeyChecking=no -o IdentitiesOnly=yes"
      ],
      var.ansible_tags != "" ? ["--tags", var.ansible_tags] : []
    )

    ansible_env_vars = [
      "ANSIBLE_ROLES_PATH=${var.ansible_dir}/playbooks/roles",
      "ANSIBLE_SCP_IF_SSH=True",
      "ANSIBLE_SSH_TRANSFER_METHOD=scp"
    ]
  }

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
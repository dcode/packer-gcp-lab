variable "commit" {
  type    = string
  default = "0000000"
}

variable "cpus" {
  type    = string
  default = "4"
}

variable "disk_size" {
  type    = string
  default = "51200"
}

variable "display" {
  type    = string
  default = "gtk"
}

variable "driver_iso_dir" {
  type    = string
  default = "./packer_cache/virtio-win"
}

variable "gcp_project" {
  type    = string
  default = "${env("GCP_PROJECT")}"
}

variable "gcs_bucket" {
  type    = string
  default = "${env("GCS_BUCKET")}"
}

variable "gcp_account_file" {
  type    = string
  default = "${env("GCS_CREDS_FILE")}"
}

variable "headless" {
  type    = string
  default = "false"
}

variable "home" {
  type    = string
  default = "${env("HOME")}"
}

variable "iso_checksum" {
  type    = string
  default = "026607e7aa7ff80441045d8830556bf8899062ca9b3c543702f112dd6ffe6078"
}

variable "iso_url" {
  type    = string
  default = "${env("ISO_URL")}"
}

variable "memory" {
  type    = string
  default = "8192"
}

variable "image_family" {
  type    = string
  default = "windows"
}

variable "qemu_accelerator" {
  type    = string
  default = "kvm"
}

variable "version" {
  type    = string
  default = "0.0.1"
}

variable "windows_version" {
  type    = string
  default = "10"
}

variable "winrm_password" {
  type    = string
  default = "admin"
}

variable "winrm_username" {
  type    = string
  default = "admin"
}

## These are used by the build script but not packer. Adding here to avoid warnings.
variable "name" {
  type    = string
  default = ""
}

variable "sha256" {
  type    = string
  default = ""
}

variable "environment" {
  type    = string
  default = ""
}

variable "driver_iso_url" {
  type    = string
  default = ""
}

variable "driver_iso_sha256" {
  type    = string
  default = ""
}

variable "template" {
  type    = string
  default = ""
}


# "timestamp" template function replacement
locals { timestamp = regex_replace(timestamp(), "[- TZ:]", "") }
# The "legacy_isotime" function has been provided for backwards compatability, but we recommend switching to the timestamp and formatdate functions.

# All locals variables are generated from variables that uses expressions
# that are not allowed in HCL2 variables.
# Read the documentation for locals blocks here:
# https://www.packer.io/docs/templates/hcl_templates/blocks/locals
locals {
  autounattend = "installer-configs/windows-${var.windows_version}/Autounattend.xml"
  build_date   = "${legacy_isotime("20060102")}"
  build_number = "${legacy_isotime("20060102")}"
}

# source blocks are generated from your builders; a source can be referenced in
# build blocks. A build block runs provisioner and post-processors on a
# source. Read the documentation for source blocks here:
# https://www.packer.io/docs/templates/hcl_templates/blocks/source
# could not parse template for following block: "template: hcl2_upgrade:2: bad character U+0060 '`'"

source "qemu" "windows-iso" {
  accelerator  = var.qemu_accelerator
  boot_command = []
  boot_wait    = "6m"
  cd_files     = ["${var.driver_iso_dir}/*"]
  floppy_files = [
    local.autounattend,
    "./files/WindowsPowershell.lnk",
    "./files/PinTo10.exe",
    "./scripts/windows/fixnetwork.ps1",
    "./scripts/windows/rearm-windows.ps1",
    "./scripts/windows/disable-screensaver.ps1",
    "./scripts/windows/disable-winrm.ps1",
    "./scripts/windows/enable-winrm.ps1",
    "./scripts/windows/microsoft-updates.bat",
    "./scripts/windows/win-updates.ps1",
    "./scripts/windows/unattend.xml",
    "./scripts/windows/sysprep.bat"
  ]
  output_directory = "output/${var.image_family}-qemu-install"
  communicator     = "winrm"
  cpus             = var.cpus
  disk_cache       = "unsafe"
  disk_interface   = "virtio-scsi"
  disk_size        = var.disk_size
  display          = var.display
  format           = "qcow2"
  headless         = var.headless
  iso_checksum     = var.iso_checksum
  iso_urls         = [var.iso_url]
  memory           = var.memory
  net_device       = "virtio-net"
  shutdown_command = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer Shutdown\""
  shutdown_timeout = "2h"
  vm_name          = "disk.qcow2"
  winrm_password   = var.winrm_password
  winrm_timeout    = "12h"
  winrm_username   = var.winrm_username
}

build {
  name = "install"

  sources = ["source.qemu.windows-iso"]

  post-processor "checksum" {
    checksum_types      = ["sha1", "sha256"]
    output              = "output/${var.image_family}-${source.type}-install/disk.qcow2.{{.ChecksumType}}"
    keep_input_artifact = true
  }
}

source "qemu" "windows-base" {
  iso_url              = "output/${var.image_family}-qemu-install/disk.qcow2"
  iso_checksum         = "file:./output/${var.image_family}-qemu-install/disk.qcow2.sha256"
  iso_target_extension = "qcow2"
  disk_image           = true
  floppy_files         = ["./scripts/windows/unattend.xml", "./scripts/windows/sysprep.bat"]
  cd_files             = ["${var.driver_iso_dir}/*"]
  accelerator          = var.qemu_accelerator
  boot_command         = []
  communicator         = "winrm"
  cpus                 = var.cpus
  disk_cache           = "unsafe"
  disk_interface       = "virtio-scsi"
  disk_size            = var.disk_size
  display              = var.display
  headless             = var.headless
  memory               = var.memory
  net_device           = "virtio-net"
  shutdown_command     = ""
  shutdown_timeout     = "2h"
  winrm_password       = var.winrm_password
  winrm_timeout        = "12h"
  winrm_username       = var.winrm_username
}

build {

  name = "baseline"

  source "qemu.windows-base" {
    name             = "gcp"
    output_directory = "output/${var.image_family}-baseline-gcp"
    format           = "raw"
    vm_name          = "disk.raw"
  }

  source "qemu.windows-base" {
    name             = "kvm"
    output_directory = "output/${var.image_family}-baseline-kvm"
    format           = "qcow2"
    vm_name          = "disk.qcow2"
  }

  provisioner "powershell" {
    scripts = [
      "./scripts/windows/install-latest-powershell.ps1",
      "./scripts/windows/install-chocolatey.ps1",
    ]
    execution_policy = "unrestricted"
  }

  provisioner "ansible" {
    playbook_file = "./ansible/playbook.yml"
    use_proxy     = false
    ansible_env_vars = ["ANSIBLE_KEEP_REMOTE_FILES=1"]
    extra_arguments = [
      "-e", "ansible_winrm_server_cert_validation=ignore",
      "-e", "ansible_winrm_scheme=http",
      "-e", "ansible_user=${var.winrm_username}",
      "-e", "ansible_winrm_read_timeout_sec=60",
      "-vv"
    ]
  }

  provisioner "powershell" {
    scripts = ["./scripts/windows/debloat-windows.ps1"]
  }

  provisioner "powershell" {
    execution_policy = "unrestricted"
    scripts          = ["./scripts/windows/gce-windows.ps1"]
    only             = ["qemu.gcp"]
  }

  provisioner "powershell" {
    debug_mode = 1
    execution_policy = "unrestricted"
    scripts = ["./scripts/windows/install-qemu-agent.ps1"]
    only = ["qemu.kvm"]
  }

  provisioner "windows-shell" {
    execute_command = "{{ .Vars }} cmd /c \"{{ .Path }}\""
    remote_path     = "/tmp/script.bat"
    scripts         = ["./scripts/windows/compile-dotnet-assemblies.bat", "./scripts/windows/set-winrm-automatic.bat", "./scripts/windows/dis-updates.bat"]
  }

  provisioner "powershell" {
    scripts = ["./scripts/windows/optimize-image.ps1"]
  }
  
  # Reboot to finalize any installs before sysprep
  provisioner "windows-restart" {}

  provisioner "powershell" {
    scripts = ["./scripts/windows/run-sysprep.ps1"]
    only    = ["qemu.gcp"]
  }

  provisioner "windows-shell" {
    execute_command = "{{ .Vars }} cmd /c \"{{ .Path }}\""
    inline = ["A:\\sysprep.bat"]
    only    = ["qemu.kvm"]
  }

  post-processors {
    post-processor "compress" {
      name   = "lz4-compress"
      output = "output/${var.image_family}_${source.type}_${build.name}.lz4"
      keep_input_artifact = true
      only   = ["qemu.kvm"]
    }
  }

  post-processors {
    post-processor "compress" {
      name   = "gcp-import"
      output = "output/${var.image_family}_${source.type}_${build.name}.tar.gz"
      keep_input_artifact = true
      only   = ["qemu.gcp"]
    }
    post-processor "googlecompute-import" {
      account_file            = "${var.gcp_account_file}"
      bucket                  = "${var.gcs_bucket}"
      project_id              = "${var.gcp_project}"
      image_description       = "Microsoft, Windows ${var.windows_version}, built on ${local.build_date} with Packer."
      image_family            = var.image_family
      image_guest_os_features = ["WINDOWS", "MULTI_IP_SUBNET", "VIRTIO_SCSI_MULTIQUEUE"]
      image_labels = {
        build_number = "${local.build_number}"
        buildstamp   = "${local.timestamp}"
        commit       = "${var.commit}"
      }
      image_name = "${var.image_family}-${local.build_date}"
      only       = ["qemu.gcp"]
    }
  }
}

# Nuevas variables

variable "template_vm_id" {
  description = "VMID de la template (ej: 9001, 9024, etc.)"
  type        = number
  default = 910
}

resource "proxmox_virtual_environment_vm" "cloudinit_test" {

  for_each = var.vms

  node_name   = var.node_name
  vm_id       = tonumber(each.key)
  name        = each.value.name
  tags        = each.value.tags

  operating_system {
    type = "win11"
  }

  description = "Cloned from template ${var.template_vm_id}"
  on_boot = true
  started = true

  machine       = "q35"
  bios          = "ovmf"
  # Controlador SCSI "VirtIO SCSI single"
  scsi_hardware = "virtio-scsi-single"

  cpu {
    cores   = each.value.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  # Clonar desde template
  clone {
    vm_id = var.template_vm_id
    full  = true
    # Si template está en otro nodo:
    # node_name = var.node_name
  }
  
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
    # vlan_id = 256 # por si fuera necesario VLAN
  }

  lifecycle {
    prevent_destroy = true
  }


  # Cloud-init drive + configuración
  initialization {
    # Cloud-init drive
    datastore_id = "local-lvm"
    interface    = "ide2"
    type         = "configdrive2" # recomendado para Windows 

    user_account {
      username = "Administrador"
      password = var.vm_passwords[each.key]
    }

    ip_config {
      ipv4 {
        address = each.value.ip_cidr
        gateway = each.value.gw
      }
    }

    # DNS desde aquí:
    dns {
       servers = ["192.168.137.10"]
    }
  }

  # Disco de datos SOLO para el FS
  dynamic "disk" {
    for_each = contains(each.value.tags, "fs") ? [1] : []
    content {
      datastore_id = var.disk_storage
      interface    = "scsi1"
      size         = 1

      cache    = "none"
      discard  = "on"
      iothread = true
      aio      = "io_uring"
      backup   = true

      # pon true SOLO si el almacenamiento del host es SSD/NVMe
      ssd = true
    }
  }

  
}
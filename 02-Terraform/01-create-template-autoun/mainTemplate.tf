
# SCRIPT DE TERRAFORM PARA CREAR LA TEMPLATE
resource "proxmox_virtual_environment_vm" "ws2025" {
  
  for_each  = var.ws2025_tmp_name
  
  name      = each.key
  node_name = var.node_name
  vm_id     = var.vm_id
  tags      = ["terraform", "template","ws2025", "uefi", "autoun"]

  # uefi
  bios = "ovmf"
  machine = "q35"

  efi_disk {
    datastore_id      = var.disk_storage
    file_format       = "raw"
    type              = "4m"
    pre_enrolled_keys = true
  }

  cpu {
    cores = max(var.cpu_cores, 2)
    type = "host"
  }

  memory {
    dedicated = var.mem_mb
  }

  network_device {
    bridge = var.bridge
    model  = "e1000"
  }

  disk {
    datastore_id = var.disk_storage
    interface    = "sata0"
    size         = var.disk_gb
  }

  cdrom {
    interface = "ide2"
    file_id   = "${var.iso_storage}:iso/${var.iso_ws2025}"
  }

  boot_order = ["sata0", "ide2"]

  # evita que cambios futuros al CD-ROM provoquen reprovisiones
  lifecycle {
    ignore_changes = [cdrom]
  }

}




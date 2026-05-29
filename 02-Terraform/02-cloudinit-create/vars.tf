variable "proxmox_endpoint" {
  description = "Proxmox API endpoint"
  type        = string
  default     = "https://192.168.137.2:8006/api2/json"
}

variable "api_token" {
  description = "API TOKEN"
  type        = string
  sensitive   = true
}

# Infra Proxmox 
variable "proxmox_ssh_host" {
  description = "Host/IP del nodo Proxmox para SSH"
  type        = string
  default     = "192.168.137.2"
}

variable "node_name" {
  type    = string
  default = "tfg"
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "disk_storage" {
  type    = string
  default = "local-lvm"
}

variable "iso_storage" {
  type    = string
  default = "local"
}

# --- Parámetros comunes VM ---
variable "cpu_cores" {
  type    = number
  default = 2
}

variable "mem_mb" {
  type    = number
  default = 4096
}

variable "disk_gb" {
  type    = number
  default = 30
}


# Nombres de ISO (fichero exacto subido a local:iso/)
variable "iso_ws2025" {
  type    = string
  default = "WindowsServer2025-Autoun-uefi.iso"
}

variable "iso_w11" {
  type    = string
  default = "Windows11-Autoun.iso"
}

variable "vm_passwords" {
  description = "Password bootstrap por VMID"
  type        = map(string)
  sensitive   = true
}

# En secrets.auto.tfvars:
# vm_passwords = {
#   "100" = "DC_local!2026"
#   "110" = "FS_local!2026"
#   "120" = "CLI_local!2026"
# }

variable "vms" {
  description = "VMs a crear: vm_id => config"
  type = map(object({
    name   = string
    ip_cidr = string
    gw     = string
    memory = number
    cores  = number
    tags   = list(string)
  }))

  default = {
    100 = {
      name    = "DC1"
      ip_cidr = "192.168.137.10/24"
      gw      = "192.168.137.1"
      memory  = 6144
      cores   = 3
      tags    = ["terraform", "ws2025", "dc"]
    }
    110 = {
      name    = "FS2"
      ip_cidr = "192.168.137.11/24"
      gw      = "192.168.137.1"
      memory  = 5120
      cores   = 2
      tags    = ["terraform", "ws2025", "fs"]
    }
    120 = {
      name    = "CLI1"
      ip_cidr = "192.168.137.12/24"
      gw      = "192.168.137.1"
      memory  = 5120
      cores   = 2
      tags    = ["terraform", "ws2025", "client"]
    } 
    
  }
}

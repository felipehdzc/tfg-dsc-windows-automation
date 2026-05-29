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

# --- Infra Proxmox ---
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


variable "ws2025_tmp_name" {
  type    = set(string)
  default = ["ws2025-TEMPLATE"]
}

variable "vm_id" {
  description = "VMID para la nueva VM"
  type        = number
  default = 900
}

variable "cpu_cores" {
  type    = number
  default = 6
}

variable "mem_mb" {
  type    = number
  default = 12288
}

variable "disk_gb" {
  type    = number
  default = 35
}


# Nombres de ISO (fichero exacto subido a local:iso/)
variable "iso_ws2025" {
  type    = string
  default = "WindowsServer2025-Autoun-uefi.iso"
}

variable "iso_w11" {
  type    = string
  default = "Windows11-Autoun-uefi.iso"
}


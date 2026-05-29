terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.57.0"
    }
  }
  required_version = ">= 1.0"
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint

  # API token:
  #api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  api_token = var.api_token

  insecure = true

  ssh {
    agent    = true
    username = "terraform"
  }

}
variable "cloudflare_email" {
  default = "petr.ruzicka@gmail.com"
}

variable "cloudflare_api_key" {}

variable "my_name" {
  default = "infra"
}

variable "my_domain" {
  default = "xvx.cz"
}

variable "fingerprint" {}

variable "instance_shape" {
  default = "VM.Standard.E2.1.Micro"
}

variable "prefix" {
  default = "my"
}

variable "private_key_path" {
  default = "~/.oci/oci_api_key.pem"
}

variable "region" {
  default = "eu-frankfurt-1"
}

variable "ssh_public_key" {
  default = "~/.ssh/id_rsa.pub"
}

variable "user_ocid" {}

variable "tags" {
  default = {
    "Owner"       = "Petr Ruzicka"
    "Environment" = "Infra"
    "Email"       = "petr.ruzicka@gmail.com"
  }
}

variable "tenancy_ocid" {}

variable "vcn_cidr_block" {
  default = "172.16.0.0/16"
}

variable "vm_count" {
  default = 1
}

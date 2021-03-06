variable "credentials" {
  type        = string
  description = "JSON credentials granting access to GCP"
  default     = ""
}

variable "project_id" {
  type        = string
  description = "The ID of the primary GCP project"
}

variable "prefix" {
  type        = string
  description = "Common prefix to use on resources"
  default     = "terraform"
}

variable "domain" {
  type        = string
  description = "Site Domain"
}

variable "bootstrap_token" {
  type        = string
  description = "Token to use for bootstraping the Hashicorp cluster"
  default     = "generate"
}

variable "server_name" {
  type        = string
  description = "Name of the bootstrap instance"
  default     = "hashicorp-bootstrap"
}

variable "server_size" {
  type        = string
  description = "Instance size of the bootstrap server"
  default     = "g1-small"
}

variable "base_image" {
  type        = string
  description = "Base image to use for bootstraping server"
  default     = "debian-10"
}

variable "region" {
  type        = string
  description = "Region in which to start bootstrap instance"
}

variable "zone" {
  type        = string
  description = "Zone in which to start bootstrap instance"
}

variable "consul_version" {
  type    = string
  default = "1.7.2"
}

variable "vault_version" {
  type    = string
  default = "1.4.0-rc1"
}

variable "vault_recovery_threshold" {
  type        = number
  description = "Number of key shares required to reconstruct the recovery key"
}

variable "vault_recovery_pgp_keys" {
  type        = string
  description = "Generated unseal keys will be encrypted and base64-encoded in the order specified in this list"
}

variable "vault_root_token_pgp_key" {
  type        = string
  description = "Generated root token will be encrypted and base64-encoded with the given public key"
}

variable "consul_encryption_key" {
  type        = string
  description = "Consul traffic encryption key"
  default     = "generate"
}

variable "secure_vms" {
  type        = list(string)
  description = "If `base_image` is found in this array, will use secure instance settings"
  default     = ["debian-10"]
}

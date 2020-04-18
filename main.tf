provider "google" {
  credentials = file(var.credentials_file)
  project     = var.project_id
  version     = "~> 3.0.0"
}

provider "random" {
  version = "~> 2.2.0"
}

resource "random_uuid" "bootstrap_token" {}

resource "random_password" "consul_encryption_key" {
  length = 32
}

locals {
  bootstrap_token       = (var.bootstrap_token == "generated") ? random_uuid.bootstrap_token.result : var.bootstrap_token
  consul_encryption_key = (var.consul_encryption_key == "generated") ? random_password.consul_encryption_key.result : var.consul_encryption_key
}

/*****
 * Enable APIs
 */
resource "google_project_service" "primary_cloudresourcemanager" {
  service = "cloudresourcemanager.googleapis.com"
}
resource "google_project_service" "primary_serviceusage" {
  service = "serviceusage.googleapis.com"
}
resource "google_project_service" "primary_cloudkms" {
  service = "cloudkms.googleapis.com"
}

/*****
 * Hashicorp Base
 */

data "google_iam_policy" "vault_kms" {
  binding {
    role    = "roles/owner"
    members = ["serviceAccount:${google_service_account.hashicorp_vault.email}"]
  }
}

resource "google_service_account" "hashicorp_vault" {
  account_id   = "hashicorp-vault"
  display_name = "Hashicorp Vault"
  description  = "Allow Hashicorp Vault access to various Google Services"
}

resource "google_kms_key_ring" "vault" {
  name       = "vault-keyring"
  location   = "global"
  depends_on = [google_project_service.primary_cloudkms]

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_key_ring_iam_policy" "vault_keyring" {
  key_ring_id = google_kms_key_ring.vault.id
  policy_data = data.google_iam_policy.vault_kms.policy_data
}

resource "google_kms_crypto_key" "vault_seal" {
  name     = "vault-seal"
  key_ring = google_kms_key_ring.vault.id

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_compute_instance" "bootstrap" {
  name         = var.server_name
  machine_type = var.server_size

  tags = ["hashicorp-server", "bootstrap"]

  boot_disk {
    initialize_params {
      image = var.base_image
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  shielded_instance_config {
    enable_secure_boot = true
    enable_vtpm        = true
  }

  metadata_startup_script = templatefile(
    "${path.module}/files/startup_script.sh",
    {
      domain                = var.domain
      bootstrap_token       = local.bootstrap_token
      consul_encryption_key = local.consul_encryption_key
      consul_version        = var.consul_version
      vault_version         = var.vault_version
  })

  service_account {
    email  = google_service_account.hashicorp_vault.email
    scopes = ["https://www.googleapis.com/auth/cloudkms"]
  }

  allow_stopping_for_update = true
}

resource "google_compute_firewall" "external_hashicorp" {
  name    = "${var.prefix}-external-hashicorp-bootstrap"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22", "8500", "8501", "8200", "4646"]
  }

  target_tags = ["bootstrap"]
}

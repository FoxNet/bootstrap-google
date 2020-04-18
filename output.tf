output "public_ip" {
  value       = google_compute_instance.bootstrap.network_interface.0.network_ip
  description = "Public IP of bootstrap instance"
  sensitive   = false
}

output "bootstrap_token" {
  value       = local.bootstrap_token
  description = "Token used to bootstrap the Hashicorp cluster_size"
  sensitive   = true
}

output "consul_encryption_key" {
  value       = local.consul_encryption_key
  description = "Consul traffic encryption key"
  sensitive   = true
}

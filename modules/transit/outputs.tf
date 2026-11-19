output "path" {
  description = "Mount path of the engine."
  value       = vault_mount.main.path
}

output "keys" {
  description = "Names of the keys the module generated."
  value       = keys(vault_transit_secret_backend_key.main)
}

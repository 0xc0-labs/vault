output "path" {
  description = "Mount path of the auth method."
  value       = vault_jwt_auth_backend.main.path
}

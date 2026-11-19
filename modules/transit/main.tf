# The engine; the operator imports the keys someone else issued (README, Transit).
resource "vault_mount" "main" {
  path        = var.path
  type        = "transit"
  description = var.description

  # Recreating the mount deletes every key in it.
  lifecycle {
    prevent_destroy = true
  }
}

# Keys Vault generates. One that signs for a trust root cannot be replaced by
# recreating it: removing one is the operator's explicit step.
resource "vault_transit_secret_backend_key" "main" {
  for_each = var.keys

  backend          = vault_mount.main.path
  name             = each.key
  type             = each.value
  exportable       = false
  deletion_allowed = false

  lifecycle {
    prevent_destroy = true
  }
}

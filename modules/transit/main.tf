# Keys live here and never leave: Vault signs or encrypts with them. The
# module creates the engine only; a key is imported by the operator (README,
# Transit), never written by OpenTofu.
resource "vault_mount" "main" {
  path        = var.path
  type        = "transit"
  description = var.description

  # Recreating the mount deletes every key in it.
  lifecycle {
    prevent_destroy = true
  }
}

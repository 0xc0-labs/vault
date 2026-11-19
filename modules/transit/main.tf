# The engine only: the operator imports its keys (README, Transit).
resource "vault_mount" "main" {
  path        = var.path
  type        = "transit"
  description = var.description

  # Recreating the mount deletes every key in it.
  lifecycle {
    prevent_destroy = true
  }
}

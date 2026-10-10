resource "vault_auth_backend" "main" {
  type        = "approle"
  path        = var.path
  description = "Machines outside the cluster and CI, one role each"

  # Every machine's way in: losing it takes each of its roles again.
  lifecycle {
    prevent_destroy = true
  }
}

# The role ID is the role's name: not a secret, so the machine's configuration
# names it. The secret ID is, and the operator writes it by hand (README,
# AppRole); it never expires on its own.
resource "vault_approle_auth_backend_role" "main" {
  for_each = var.roles

  backend   = vault_auth_backend.main.path
  role_name = each.key
  role_id   = each.key

  bind_secret_id     = true
  secret_id_ttl      = 0
  secret_id_num_uses = 0

  # Batch: one short-lived token per use, never renewed.
  token_type     = "batch"
  token_policies = each.value.policies
  token_ttl      = each.value.token_ttl
  token_max_ttl  = each.value.token_ttl
}

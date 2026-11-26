resource "vault_github_auth_backend" "main" {
  path         = var.path
  description  = "The organization's people, with a personal GitHub token"
  organization = var.organization

  token_ttl     = var.token_ttl
  token_max_ttl = var.token_max_ttl

  # The people's way in: losing it takes a bootstrap with the root token.
  lifecycle {
    prevent_destroy = true
  }
}

resource "vault_github_team" "main" {
  for_each = var.teams

  backend  = vault_github_auth_backend.main.path
  team     = each.key
  policies = each.value
}

resource "vault_jwt_auth_backend" "main" {
  path               = var.path
  description        = "GitHub Actions OIDC tokens"
  oidc_discovery_url = var.issuer
  bound_issuer       = var.issuer

  # The CI's only way in: losing it takes a bootstrap with the root token.
  lifecycle {
    prevent_destroy = true
  }
}

resource "vault_jwt_auth_backend_role" "main" {
  for_each = var.roles

  backend   = vault_jwt_auth_backend.main.path
  role_name = each.key
  role_type = "jwt"

  bound_audiences   = [var.audience]
  bound_claims_type = each.value.claims_type
  bound_claims      = each.value.bound_claims
  # One entity per calling workflow.
  user_claim = "job_workflow_ref"

  token_policies = each.value.policies
  token_ttl      = each.value.token_ttl
  token_max_ttl  = each.value.token_ttl

  lifecycle {
    prevent_destroy = true
  }
}

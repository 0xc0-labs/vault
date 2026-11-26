resource "vault_jwt_auth_backend" "main" {
  path               = var.path
  type               = "oidc"
  description        = "The organization's people, through Cloudflare Access"
  oidc_discovery_url = var.discovery_url
  oidc_client_id     = var.client_id
  oidc_client_secret = var.client_secret
  default_role       = var.default_role

  # So the UI offers the method without typing its path.
  tune {
    listing_visibility = "unauth"
  }

  # Recreating the mount revokes every token its logins issued.
  lifecycle {
    prevent_destroy = true
  }
}

resource "vault_jwt_auth_backend_role" "main" {
  for_each = var.roles

  backend   = vault_jwt_auth_backend.main.path
  role_name = each.key
  role_type = "oidc"

  # Cloudflare's Access application admits who may log in and issues a token
  # for nobody else, so the audience is the only binding the role needs.
  bound_audiences       = [var.client_id]
  user_claim            = "email"
  oidc_scopes           = ["openid", "email", "profile"]
  allowed_redirect_uris = each.value.allowed_redirect_uris

  token_policies = each.value.policies
  token_ttl      = var.token_ttl
  token_max_ttl  = var.token_max_ttl

  lifecycle {
    prevent_destroy = true
  }
}

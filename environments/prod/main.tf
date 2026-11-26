module "github_jwt" {
  source = "../../modules/github-jwt-auth"

  audience = var.jwt_audience
  roles    = var.jwt_roles
}

module "github_auth" {
  source = "../../modules/github-auth"

  organization = var.github_organization
  teams        = var.github_teams
}

module "oidc_auth" {
  source = "../../modules/oidc-auth"

  discovery_url = "https://0xc0.cloudflareaccess.com/cdn-cgi/access/sso/oidc/${var.oidc_client_id}"
  client_id     = var.oidc_client_id
  client_secret = var.oidc_client_secret
  default_role  = "admins"
  roles         = var.oidc_roles
}

module "policies" {
  source = "../../modules/policy"
  for_each = merge(
    { for f in fileset("${path.root}/../../policies", "*.hcl") : trimsuffix(f, ".hcl") => f },
    { for f in fileset("${path.root}/../../policies", "*.hcl.tftpl") : trimsuffix(f, ".hcl.tftpl") => f },
  )

  name = each.key
  policy = endswith(each.value, ".tftpl") ? templatefile("${path.root}/../../policies/${each.value}", {
    kubernetes_accessor = module.kubernetes_auth.accessor
  }) : file("${path.root}/../../policies/${each.value}")
}

module "kubernetes_auth" {
  source = "../../modules/kubernetes-auth"

  roles = var.kubernetes_roles
}

module "kv" {
  source   = "../../modules/kv"
  for_each = var.kv_engines

  path        = each.key
  description = each.value
}

module "transit" {
  source = "../../modules/transit"

  description = "Keys that never leave Vault: it signs and encrypts with them"
}

module "approle_auth" {
  source = "../../modules/approle-auth"

  roles = var.approle_roles
}

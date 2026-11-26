variable "jwt_audience" {
  description = "The aud claim the CI jobs' OIDC tokens carry: Vault's own address, as the reusable workflows ask GitHub for it."
  type        = string
}

variable "jwt_roles" {
  description = "The JWT auth roles, by name: the claims a token must match, its policies, and its TTL in seconds."
  type = map(object({
    bound_claims = map(string)
    claims_type  = optional(string, "string")
    policies     = list(string)
    token_ttl    = optional(number, 1200)
  }))
}

variable "github_organization" {
  description = "The GitHub organization whose members may log in to Vault."
  type        = string
}

variable "github_teams" {
  description = "The GitHub auth method's teams, by slug: the policies a member gets."
  type        = map(list(string))
  default     = {}
}

variable "oidc_client_id" {
  description = "The client ID of Cloudflare Access's OIDC application for Vault, from platform/vault/oidc."
  type        = string
  sensitive   = true
}

variable "oidc_client_secret" {
  description = "The client secret of that application, from platform/vault/oidc."
  type        = string
  sensitive   = true
}

variable "oidc_roles" {
  description = "The OIDC auth method's roles, by name: the policies a login gets and the redirect URIs it may use."
  type = map(object({
    policies              = list(string)
    allowed_redirect_uris = list(string)
  }))
  default = {}
}

variable "kubernetes_roles" {
  description = "Kubernetes auth roles, one per namespace and named after it, or one for the namespaces carrying a label: the namespace or the labels, its service accounts, their audience, its policies and TTL."
  type = map(object({
    namespace        = optional(string)
    namespace_labels = optional(map(string))
    service_accounts = list(string)
    audience         = optional(string, "vault")
    policies         = list(string)
    token_ttl        = optional(number, 3600)
  }))
  default = {}
}

variable "kv_engines" {
  description = "KV v2 secrets engines, by mount path, each with what it holds."
  type        = map(string)
}

variable "approle_roles" {
  description = "AppRole roles, by name (also their role ID): the policies a login gets, and its token's TTL in seconds."
  type = map(object({
    policies  = list(string)
    token_ttl = optional(number, 60)
  }))
  default = {}
}

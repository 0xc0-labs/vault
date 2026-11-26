variable "path" {
  description = "Mount path of the auth method."
  type        = string
  default     = "oidc"
}

variable "discovery_url" {
  description = "The OIDC issuer: Vault reads its discovery document and keys from here."
  type        = string
}

variable "client_id" {
  description = "The OIDC application's client ID, which is also the audience of its tokens."
  type        = string
}

variable "client_secret" {
  description = "The OIDC application's client secret."
  type        = string
  sensitive   = true
}

variable "default_role" {
  description = "The role a login uses when it names none."
  type        = string
}

variable "roles" {
  description = "Roles by name: the policies a login gets and the redirect URIs it may use."
  type = map(object({
    policies              = list(string)
    allowed_redirect_uris = list(string)
  }))
}

variable "token_ttl" {
  description = "Lifetime of a login's token, in seconds."
  type        = number
  default     = 28800
}

variable "token_max_ttl" {
  description = "Longest a login's token can be renewed to, in seconds."
  type        = number
  default     = 86400
}

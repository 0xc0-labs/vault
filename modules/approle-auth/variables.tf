variable "path" {
  description = "Mount path of the auth method."
  type        = string
  default     = "approle"
}

variable "roles" {
  description = "Roles by name, which is also their role ID: the policies a login gets, and its token's TTL in seconds."
  type = map(object({
    policies  = list(string)
    token_ttl = optional(number, 60)
  }))
}

variable "path" {
  description = "Mount path of the auth method."
  type        = string
  default     = "github"
}

variable "organization" {
  description = "The GitHub organization whose members may log in."
  type        = string
}

variable "teams" {
  description = "Policies by team slug: a member of the team gets them."
  type        = map(list(string))
  default     = {}
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

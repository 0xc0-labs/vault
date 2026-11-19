variable "path" {
  description = "Mount path of the engine."
  type        = string
  default     = "transit"
}

variable "description" {
  description = "What the engine's keys are for."
  type        = string
}

variable "keys" {
  description = "Keys Vault generates, by name, each with its type. Never exportable, never deletable. A key someone else issued is imported by the operator, not declared here."
  type        = map(string)
  default     = {}
}

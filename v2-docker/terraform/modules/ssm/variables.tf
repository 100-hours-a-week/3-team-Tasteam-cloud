variable "environment" {
  description = "Environment name (prod, dev, stg)"
  type        = string
}

variable "parameters" {
  description = "Map of SSM parameters to create. Key = path suffix, value = { type, description }"
  type = map(object({
    type        = string # "String" or "SecureString"
    description = string
  }))
}

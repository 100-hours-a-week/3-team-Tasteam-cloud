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

  validation {
    condition = alltrue([
      for k, _ in var.parameters : can(regex("^(backend|frontend)/[A-Z0-9_]+$|^(fastapi|monitoring)/[a-z0-9-]+(?:/[a-z0-9-]+)*$", k))
    ])
    error_message = "SSM parameter key must match one of: backend|frontend with UPPER_SNAKE_CASE (e.g. backend/DB_URL), or fastapi|monitoring with slash+kebab-case (e.g. fastapi/openai-api-key)."
  }
}

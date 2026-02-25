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
      for k, _ in var.parameters : can(regex("^(backend|frontend|fastapi|monitoring)/[A-Z0-9_]+$", k))
    ])
    error_message = "SSM parameter key must use UPPER_SNAKE_CASE for all namespaces (e.g. backend/DB_URL, fastapi/OPENAI_API_KEY, monitoring/GRAFANA_ADMIN_PASSWORD)."
  }
}

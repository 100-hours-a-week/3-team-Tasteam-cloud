variable "environment" {
  description = "Environment name (shared, dev, prod, stg)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to create security groups in"
  type        = string
}

variable "shared_vpc_cidr" {
  description = "shared VPC CIDR — Prometheus scrape 허용용 (null이면 규칙 미생성)"
  type        = string
  default     = null
}

variable "enable_monitoring" {
  description = "Whether to create monitoring security group"
  type        = bool
  default     = false
}

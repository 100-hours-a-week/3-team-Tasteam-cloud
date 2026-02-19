variable "environment" {
  description = "Environment name (shared, dev, prod, stg)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to create security groups in"
  type        = string
}

variable "enable_monitoring" {
  description = "Whether to create monitoring security group"
  type        = bool
  default     = false
}

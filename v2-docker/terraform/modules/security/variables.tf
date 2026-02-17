variable "environment" {
  description = "Environment name (shared, dev, prod, stg)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to create security groups in"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "key_name" {
  description = "EC2 key pair name for SSH access"
  type        = string
  default     = null
}

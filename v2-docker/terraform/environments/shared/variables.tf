variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "shared"
}

variable "key_name" {
  description = "EC2 key pair name for SSH access"
  type        = string
  default     = null
}

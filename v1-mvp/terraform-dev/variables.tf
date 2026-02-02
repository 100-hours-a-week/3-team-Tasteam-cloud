variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

variable "availability_zone" {
  description = "Availability Zone"
  type        = string
  default     = "ap-northeast-2b"
}

variable "instance_ami" {
  description = "AMI ID for the EC2 instance (custom AMI from production)"
  type        = string
  default     = "ami-0e574d15e1aa353fe"
}

variable "instance_type" {
  description = "EC2 Instance Type"
  type        = string
  default     = "c7i-flex.large"
}

variable "key_name" {
  description = "Key pair name (shared with production)"
  type        = string
  default     = "key-pair-mvp"
}

variable "instance_name" {
  description = "Name tag for the instance"
  type        = string
  default     = "development-ec2-mvp"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "development"
}

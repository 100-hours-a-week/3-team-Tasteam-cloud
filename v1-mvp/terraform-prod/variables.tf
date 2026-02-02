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
  description = "AMI ID for the EC2 instance"
  type        = string
  default     = "ami-010be25c3775061c9"
}

variable "instance_type" {
  description = "EC2 Instance Type"
  type        = string
  default     = "c7i-flex.large"
}

variable "key_name" {
  description = "Key pair name"
  type        = string
  default     = "key-pair-mvp"
}

variable "instance_name" {
  description = "Name tag for the instance"
  type        = string
  default     = "prod-ec2-mvp"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

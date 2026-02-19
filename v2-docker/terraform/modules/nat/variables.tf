variable "environment" {
  description = "Environment name (prod, dev, stg)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to create security group in"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block — NAT SG inbound 허용 범위"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID to place the NAT instance in"
  type        = string
}

variable "private_route_table_id" {
  description = "Private route table ID — 0.0.0.0/0 경로를 NAT으로 설정"
  type        = string
}

variable "ami_id" {
  description = "fck-nat AMI ID"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (prod: t4g.micro, dev: t4g.nano)"
  type        = string
  default     = "t4g.micro"
}

variable "key_name" {
  description = "EC2 key pair name for SSH access"
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 8
}

variable "environment" {
  description = "Environment name (prod, dev, stg, shared)"
  type        = string
}

variable "purpose" {
  description = "Instance purpose — Name 태그에 사용 (e.g. caddy, monitoring)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "ami_id" {
  description = "AMI ID (e.g. data.aws_ami.docker_base.id)"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID to place the instance in"
  type        = string
}

variable "security_group_ids" {
  description = "Security group IDs to attach"
  type        = list(string)
}

variable "key_name" {
  description = "EC2 key pair name for SSH access"
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 20
}

variable "associate_public_ip_address" {
  description = "Whether to assign a public IP"
  type        = bool
  default     = false
}

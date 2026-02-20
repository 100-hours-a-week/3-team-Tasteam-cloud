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
  description = "외부 제공 EC2 key pair name (manage_key_pair=false 시 사용)"
  type        = string
  default     = null
}

variable "manage_key_pair" {
  description = "true 시 tls_private_key + aws_key_pair를 모듈 내에서 자동 생성"
  type        = bool
  default     = false
}

variable "private_key_output_dir" {
  description = "생성된 private key(.pem) 저장 디렉토리 절대 경로"
  type        = string
  default     = "~/.ssh"
}

variable "iam_instance_profile" {
  description = "EC2 instance profile name to attach"
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

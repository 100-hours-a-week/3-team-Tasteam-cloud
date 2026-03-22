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

variable "qdrant_ami_id" {
  description = "AMI ID baked from the staging Qdrant instance for prod Qdrant EC2"
  type        = string
  default     = "ami-02163765f33fa2c8b"
}

variable "codedeploy_app_name" {
  description = "CodeDeploy application name for backend"
  type        = string
  default     = "tasteam-backend-prod"
}

variable "codedeploy_deployment_group_name" {
  description = "CodeDeploy deployment group name for backend"
  type        = string
  default     = "tasteam-backend-prod-dg"
}

variable "db_username" {
  description = "RDS 마스터 유저 이름"
  type        = string
  default     = "postgres"
}

variable "upload_bucket_name" {
  description = "S3 bucket name for application uploads"
  type        = string
  default     = "tasteam-prod-uploads-kr"
}

variable "frontend_static_bucket_name" {
  description = "S3 bucket name for frontend static assets"
  type        = string
  default     = "tasteam-prod-frontend-static-kr"
}

variable "frontend_certificate_domain_name" {
  description = "Primary domain name for frontend CloudFront ACM certificate (must be issued in us-east-1)"
  type        = string
  default     = "tasteam.kr"
}

variable "frontend_certificate_san_names" {
  description = "Subject Alternative Names for frontend CloudFront ACM certificate"
  type        = list(string)
  default     = []
}

variable "frontend_cloudfront_aliases" {
  description = "Custom domain aliases for frontend CloudFront distribution (e.g., tasteam.kr)"
  type        = list(string)
  default     = ["tasteam.kr"]
}

variable "v1_migration_principal_arns" {
  description = "IAM principal ARNs in v1 account allowed to migrate objects into the uploads bucket"
  type        = list(string)
  default     = []
}

variable "caddy_admin_ssh_cidrs" {
  description = "Allowed admin CIDRs for SSH (22/tcp) to Caddy/app SG"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

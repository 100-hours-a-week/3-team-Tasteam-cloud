variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "stg"
}

variable "codedeploy_app_name" {
  description = "CodeDeploy application name for backend"
  type        = string
  default     = "tasteam-backend-stg"
}

variable "codedeploy_deployment_group_name" {
  description = "CodeDeploy deployment group name for backend"
  type        = string
  default     = "tasteam-backend-stg-dg"
}

variable "db_username" {
  description = "RDS 마스터 유저 이름"
  type        = string
  default     = "postgres"
}

variable "upload_bucket_name" {
  description = "S3 bucket name for application uploads"
  type        = string
  default     = "tasteam-stg-uploads-kr"
}

variable "frontend_static_bucket_name" {
  description = "S3 bucket name for frontend static assets"
  type        = string
  default     = "tasteam-stg-frontend-static-kr"
}

variable "v1_migration_principal_arns" {
  description = "IAM principal ARNs in v1 account allowed to migrate objects into the uploads bucket"
  type        = list(string)
  default     = []
}

variable "caddy_admin_ssh_cidrs" {
  description = "Allowed admin CIDRs for SSH (22/tcp) to Caddy/app SG"
  type        = list(string)
  default     = ["211.244.225.166/32"]
}

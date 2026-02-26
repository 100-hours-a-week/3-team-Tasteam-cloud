variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "codedeploy_app_name" {
  description = "CodeDeploy application name for backend"
  type        = string
  default     = "tasteam-backend-dev"
}

variable "codedeploy_deployment_group_name" {
  description = "CodeDeploy deployment group name for backend"
  type        = string
  default     = "tasteam-backend-dev-dg"
}

variable "upload_bucket_name" {
  description = "S3 bucket name for application uploads"
  type        = string
  default     = "tasteam-dev-uploads-kr"
}

variable "v1_migration_principal_arns" {
  description = "IAM principal ARNs in v1 account allowed to migrate objects into the uploads bucket"
  type        = list(string)
  default     = []
}

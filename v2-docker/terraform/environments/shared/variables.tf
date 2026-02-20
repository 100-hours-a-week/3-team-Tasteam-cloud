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

variable "github_repository" {
  description = "GitHub repository in owner/repo format"
  type        = string
  default     = "kimsj/3-team-Tasteam-be"
}

variable "codedeploy_artifact_bucket_name" {
  description = "S3 bucket name for CodeDeploy artifacts"
  type        = string
  default     = "tasteam-v2-codedeploy-artifacts"
}

variable "github_oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN. Leave empty to create one."
  type        = string
  default     = ""
}

variable "ecr_repository_backend_name" {
  description = "ECR repository name for backend image"
  type        = string
  default     = "tasteam-be"
}

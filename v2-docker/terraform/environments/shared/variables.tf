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

variable "github_repositories" {
  description = "GitHub repositories allowed to assume the deploy role (owner/repo format)"
  type        = list(string)
  default = [
    "100-hours-a-week/3-team-Tasteam-be",
    "100-hours-a-week/3-team-Tasteam-fe",
    "100-hours-a-week/3-team-tasteam-ai",
    "100-hours-a-week/3-team-Tasteam-cloud",
  ]
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

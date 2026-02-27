output "vpc_id" {
  description = "Shared VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "Shared VPC CIDR block"
  value       = module.vpc.vpc_cidr_block
}

output "private_route_table_id" {
  description = "Shared private route table ID"
  value       = module.vpc.private_route_table_id
}

output "ec2_caddy_public_ip" {
  description = "Shared Caddy EC2 퍼블릭 IP (Grafana 프록시 진입점)"
  value       = module.ec2_caddy.public_ip
}

output "ec2_caddy_key_pair_name" {
  description = "Shared Caddy EC2 key pair name"
  value       = module.ec2_caddy.key_pair_name
}

output "ec2_caddy_private_key_path" {
  description = "Shared Caddy EC2 private key 로컬 파일 경로"
  value       = module.ec2_caddy.private_key_path
}

output "ec2_monitoring_key_pair_name" {
  description = "Shared monitoring EC2 key pair name"
  value       = module.ec2_monitoring.key_pair_name
}

output "ec2_monitoring_private_key_path" {
  description = "Shared monitoring EC2 private key 로컬 파일 경로"
  value       = module.ec2_monitoring.private_key_path
}

output "github_actions_deploy_role_arn" {
  description = "GitHub Actions deploy role ARN"
  value       = aws_iam_role.github_actions_deploy.arn
}

output "backend_readonly_paramstore_user_names" {
  description = "Backend IAM user names with ReadOnly + Parameter Store full access"
  value       = sort([for u in aws_iam_user.backend_readonly_paramstore : u.name])
}

output "backend_readonly_paramstore_user_arns" {
  description = "Backend IAM user ARNs with ReadOnly + Parameter Store full access"
  value       = { for name, user in aws_iam_user.backend_readonly_paramstore : name => user.arn }
}

output "codedeploy_artifact_bucket_name" {
  description = "S3 bucket name for CodeDeploy artifacts"
  value       = aws_s3_bucket.codedeploy_artifacts.bucket
}

output "ecr_repository_backend_name" {
  description = "Backend ECR repository name"
  value       = aws_ecr_repository.backend.name
}

output "ecr_repository_backend_url" {
  description = "Backend ECR repository URL"
  value       = aws_ecr_repository.backend.repository_url
}

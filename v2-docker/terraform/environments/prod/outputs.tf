output "vpc_id" {
  description = "Prod VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "Prod VPC CIDR block"
  value       = module.vpc.vpc_cidr_block
}

output "private_route_table_id" {
  description = "Prod private route table ID"
  value       = module.vpc.private_route_table_id
}

output "public_route_table_id" {
  description = "Prod public route table ID"
  value       = module.vpc.public_route_table_id
}

output "ec2_caddy_key_pair_name" {
  description = "Prod caddy EC2 key pair name"
  value       = module.ec2_caddy.key_pair_name
}

output "ec2_caddy_private_key_path" {
  description = "Prod caddy EC2 private key 로컬 파일 경로"
  value       = module.ec2_caddy.private_key_path
}

output "ec2_caddy_public_ip" {
  description = "Prod caddy EC2 public IP (Elastic IP, Redis SSH 점프호스트)"
  value       = module.ec2_caddy.public_ip
}

# ──────────────────────────────────────────────
# ASG Spring
# ──────────────────────────────────────────────

output "asg_spring_name" {
  description = "Spring Boot ASG 이름"
  value       = module.asg_spring.asg_name
}

output "asg_spring_arn" {
  description = "Spring Boot ASG ARN"
  value       = module.asg_spring.asg_arn
}

output "codedeploy_app_name" {
  description = "CodeDeploy application name for prod backend"
  value       = aws_codedeploy_app.backend.name
}

output "codedeploy_deployment_group_name" {
  description = "CodeDeploy deployment group name for prod backend"
  value       = aws_codedeploy_deployment_group.backend_prod.deployment_group_name
}

# ──────────────────────────────────────────────
# NAT Instance
# ──────────────────────────────────────────────

output "nat_public_ip" {
  description = "NAT 인스턴스 EIP (고정 공인 IP)"
  value       = module.nat.public_ip
}

# ──────────────────────────────────────────────
# Cloud Map
# ──────────────────────────────────────────────

output "cloud_map_service_dns" {
  description = "Caddy upstream에 사용할 Cloud Map DNS 이름"
  value       = module.cloud_map.dns_name
}

output "uploads_bucket_name" {
  description = "Prod uploads S3 bucket name"
  value       = aws_s3_bucket.uploads.bucket
}

output "frontend_static_bucket_name" {
  description = "Prod frontend static S3 bucket name"
  value       = aws_s3_bucket.frontend_static.bucket
}

output "frontend_cloudfront_distribution_id" {
  description = "CloudFront distribution ID for frontend static delivery"
  value       = aws_cloudfront_distribution.frontend.id
}

output "frontend_cloudfront_domain_name" {
  description = "CloudFront domain name for frontend static delivery"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "frontend_cloudfront_acm_certificate_arn" {
  description = "ACM certificate ARN for frontend CloudFront custom domain (us-east-1)"
  value       = aws_acm_certificate.frontend_cloudfront.arn
}

output "frontend_cloudfront_acm_dns_validation_records" {
  description = "DNS validation CNAME records for the frontend CloudFront ACM certificate"
  value = [
    for dvo in aws_acm_certificate.frontend_cloudfront.domain_validation_options : {
      domain_name  = dvo.domain_name
      record_name  = dvo.resource_record_name
      record_type  = dvo.resource_record_type
      record_value = dvo.resource_record_value
    }
  ]
}

# ──────────────────────────────────────────────
# Redis EC2
# ──────────────────────────────────────────────

output "ec2_redis_instance_id" {
  description = "Prod Redis EC2 instance ID"
  value       = module.ec2_redis.instance_id
}

output "ec2_redis_private_ip" {
  description = "Prod Redis EC2 private IP"
  value       = module.ec2_redis.private_ip
}

output "ec2_redis_key_pair_name" {
  description = "Prod Redis EC2 key pair name"
  value       = module.ec2_redis.key_pair_name
}

output "ec2_redis_private_key_path" {
  description = "Prod Redis EC2 private key 로컬 파일 경로 (점프호스트 경유 SSH 용도)"
  value       = module.ec2_redis.private_key_path
}

output "ec2_qdrant_instance_id" {
  description = "Prod Qdrant EC2 instance ID"
  value       = module.ec2_qdrant.instance_id
}

output "ec2_qdrant_private_ip" {
  description = "Prod Qdrant EC2 private IP"
  value       = module.ec2_qdrant.private_ip
}

output "ec2_qdrant_key_pair_name" {
  description = "Prod Qdrant EC2 key pair name"
  value       = module.ec2_qdrant.key_pair_name
}

output "ec2_qdrant_private_key_path" {
  description = "Prod Qdrant EC2 private key 로컬 파일 경로 (점프호스트 경유 SSH 용도)"
  value       = module.ec2_qdrant.private_key_path
}

output "qdrant_http_endpoint" {
  description = "Qdrant HTTP endpoint for FastAPI"
  value       = "http://${module.ec2_qdrant.private_ip}:6333"
}

output "qdrant_grpc_endpoint" {
  description = "Qdrant gRPC endpoint for FastAPI"
  value       = "${module.ec2_qdrant.private_ip}:6334"
}

output "rds_address" {
  description = "RDS endpoint hostname"
  value       = module.rds.address
}

output "rds_port" {
  description = "RDS port"
  value       = module.rds.port
}

output "rds_identifier" {
  description = "RDS instance identifier"
  value       = module.rds.identifier
}

# ──────────────────────────────────────────────
# Spring S3 Upload IAM Access Key
# ──────────────────────────────────────────────

output "spring_s3_access_key_id" {
  description = "S3 업로드 전용 IAM Access Key ID (SSM STORAGE_ACCESS_KEY 값으로 사용)"
  value       = aws_iam_access_key.spring_s3_upload.id
}

output "spring_s3_secret_access_key" {
  description = "S3 업로드 전용 IAM Secret Access Key (SSM STORAGE_SECRET_KEY 값으로 사용)"
  value       = aws_iam_access_key.spring_s3_upload.secret
  sensitive   = true
}

output "vpc_id" {
  description = "Stg VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "Stg VPC CIDR block"
  value       = module.vpc.vpc_cidr_block
}

output "private_route_table_id" {
  description = "Stg private route table ID"
  value       = module.vpc.private_route_table_id
}

output "public_route_table_id" {
  description = "Stg public route table ID"
  value       = module.vpc.public_route_table_id
}

output "ec2_caddy_key_pair_name" {
  description = "Stg caddy EC2 key pair name"
  value       = module.ec2_caddy.key_pair_name
}

output "ec2_caddy_private_key_path" {
  description = "Stg caddy EC2 private key 로컬 파일 경로"
  value       = module.ec2_caddy.private_key_path
}

output "ec2_caddy_public_ip" {
  description = "Stg caddy EC2 public IP"
  value       = module.ec2_caddy.public_ip
}

output "asg_spring_name" {
  description = "Stg Spring Boot ASG 이름"
  value       = module.asg_spring.asg_name
}

output "asg_spring_arn" {
  description = "Stg Spring Boot ASG ARN"
  value       = module.asg_spring.asg_arn
}

output "codedeploy_app_name" {
  description = "CodeDeploy application name for stg backend"
  value       = aws_codedeploy_app.backend.name
}

output "codedeploy_deployment_group_name" {
  description = "CodeDeploy deployment group name for stg backend"
  value       = aws_codedeploy_deployment_group.backend_stg.deployment_group_name
}

output "nat_public_ip" {
  description = "NAT 인스턴스 EIP (고정 공인 IP)"
  value       = module.nat.public_ip
}

output "cloud_map_service_dns" {
  description = "Caddy upstream에 사용할 Cloud Map DNS 이름"
  value       = module.cloud_map.dns_name
}

output "uploads_bucket_name" {
  description = "Stg uploads S3 bucket name"
  value       = aws_s3_bucket.uploads.bucket
}

output "ec2_redis_instance_id" {
  description = "Stg Redis EC2 instance ID"
  value       = module.ec2_redis.instance_id
}

output "ec2_redis_private_ip" {
  description = "Stg Redis EC2 private IP"
  value       = module.ec2_redis.private_ip
}

output "ec2_redis_key_pair_name" {
  description = "Stg Redis EC2 key pair name"
  value       = module.ec2_redis.key_pair_name
}

output "ec2_redis_private_key_path" {
  description = "Stg Redis EC2 private key 로컬 파일 경로 (점프호스트 경유 SSH 용도)"
  value       = module.ec2_redis.private_key_path
}

output "rds_address" {
  description = "RDS endpoint hostname"
  value       = module.rds.address
}

output "rds_port" {
  description = "RDS port"
  value       = module.rds.port
}

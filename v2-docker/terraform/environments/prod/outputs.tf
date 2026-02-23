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

output "ec2_caddy_key_pair_name" {
  description = "Prod caddy EC2 key pair name"
  value       = module.ec2_caddy.key_pair_name
}

output "ec2_caddy_private_key_path" {
  description = "Prod caddy EC2 private key 로컬 파일 경로"
  value       = module.ec2_caddy.private_key_path
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

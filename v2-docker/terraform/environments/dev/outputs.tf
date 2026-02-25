output "vpc_id" {
  description = "Dev VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "Dev VPC CIDR block"
  value       = module.vpc.vpc_cidr_block
}

output "private_route_table_id" {
  description = "Dev private route table ID"
  value       = module.vpc.private_route_table_id
}

output "ec2_caddy_id" {
  description = "Dev Caddy EC2 instance ID"
  value       = module.ec2_caddy.instance_id
}

output "ec2_caddy_public_ip" {
  description = "Dev Caddy EC2 public IP"
  value       = module.ec2_caddy.public_ip
}

output "ec2_spring_id" {
  description = "Dev Spring Boot EC2 instance ID"
  value       = module.ec2_spring.instance_id
}

output "ec2_spring_private_ip" {
  description = "Dev Spring Boot EC2 private IP"
  value       = module.ec2_spring.private_ip
}

output "ec2_spring_key_pair_name" {
  description = "Dev Spring Boot EC2 key pair name"
  value       = module.ec2_spring.key_pair_name
}

output "codedeploy_app_name" {
  description = "CodeDeploy application name for dev backend"
  value       = aws_codedeploy_app.backend.name
}

output "codedeploy_deployment_group_name" {
  description = "CodeDeploy deployment group name for dev backend"
  value       = aws_codedeploy_deployment_group.backend_dev.deployment_group_name
}

output "public_route_table_id" {
  description = "Dev public route table ID"
  value       = module.vpc.public_route_table_id
}

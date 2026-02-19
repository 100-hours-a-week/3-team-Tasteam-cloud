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

output "ec2_monitoring_key_pair_name" {
  description = "Shared monitoring EC2 key pair name"
  value       = module.ec2_monitoring.key_pair_name
}

output "ec2_monitoring_private_key_path" {
  description = "Shared monitoring EC2 private key 로컬 파일 경로"
  value       = module.ec2_monitoring.private_key_path
}

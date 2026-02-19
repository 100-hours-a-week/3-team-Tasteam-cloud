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

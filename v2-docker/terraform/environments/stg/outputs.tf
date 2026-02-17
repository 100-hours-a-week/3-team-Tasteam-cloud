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

output "app_sg_id" {
  description = "Application server security group ID"
  value       = aws_security_group.app.id
}

output "rds_sg_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}

output "redis_sg_id" {
  description = "Redis security group ID"
  value       = aws_security_group.redis.id
}

output "monitoring_sg_id" {
  description = "Monitoring server security group ID"
  value       = var.enable_monitoring ? aws_security_group.monitoring[0].id : null
}

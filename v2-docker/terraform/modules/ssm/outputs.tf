output "parameter_arns" {
  description = "Map of parameter name to ARN (IAM 정책 연동용)"
  value       = { for k, v in aws_ssm_parameter.this : k => v.arn }
}

output "parameter_name_prefix" {
  description = "Parameter name prefix for this environment"
  value       = "/${var.environment}/tasteam"
}

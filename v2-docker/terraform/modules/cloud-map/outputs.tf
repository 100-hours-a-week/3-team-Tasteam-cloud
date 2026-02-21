output "namespace_id" {
  description = "Cloud Map Private DNS Namespace ID"
  value       = aws_service_discovery_private_dns_namespace.this.id
}

output "namespace_hosted_zone" {
  description = "Cloud Map Namespace가 생성한 Route 53 Private Hosted Zone ID"
  value       = aws_service_discovery_private_dns_namespace.this.hosted_zone
}

output "service_id" {
  description = "Cloud Map 서비스 ID — Lambda에서 register/deregister 시 사용"
  value       = aws_service_discovery_service.this.id
}

output "service_arn" {
  description = "Cloud Map 서비스 ARN"
  value       = aws_service_discovery_service.this.arn
}

output "dns_name" {
  description = "Cloud Map 서비스 DNS 이름 (e.g. spring.internal.tasteam.local)"
  value       = "${var.service_name}.internal.tasteam.local"
}

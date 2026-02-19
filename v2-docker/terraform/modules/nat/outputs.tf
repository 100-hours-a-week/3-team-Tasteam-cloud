output "instance_id" {
  description = "NAT EC2 instance ID"
  value       = aws_instance.nat.id
}

output "public_ip" {
  description = "NAT 인스턴스 EIP (고정 공인 IP)"
  value       = aws_eip.nat.public_ip
}

output "eip_id" {
  description = "NAT EIP allocation ID"
  value       = aws_eip.nat.id
}

output "security_group_id" {
  description = "NAT security group ID"
  value       = aws_security_group.nat.id
}

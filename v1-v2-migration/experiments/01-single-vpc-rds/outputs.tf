output "source_ec2_public_ip" {
  description = "소스 EC2 퍼블릭 IP (SSH 접속용)"
  value       = aws_eip.source.public_ip
}

output "target_rds_endpoint" {
  description = "타겟 RDS 엔드포인트"
  value       = aws_db_instance.target.endpoint
}

output "target_rds_address" {
  description = "타겟 RDS 호스트 주소 (포트 제외)"
  value       = aws_db_instance.target.address
}

output "target_rds_port" {
  description = "타겟 RDS 포트"
  value       = aws_db_instance.target.port
}

output "ssh_command" {
  description = "소스 EC2 SSH 접속 명령어"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_eip.source.public_ip}"
}

output "psql_to_rds_command" {
  description = "EC2에서 RDS 접속 명령어 (EC2 내부에서 실행)"
  value       = "psql -h ${aws_db_instance.target.address} -p ${aws_db_instance.target.port} -U ${var.db_username} -d ${var.db_name}"
}

# ---------- 오케스트레이터 EC2 ----------

output "orchestrator_public_ip" {
  description = "오케스트레이터 EC2 퍼블릭 IP"
  value       = aws_eip.orchestrator.public_ip
}

output "orchestrator_ssh_command" {
  description = "오케스트레이터 EC2 SSH 접속 명령어"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_eip.orchestrator.public_ip}"
}

output "orchestrator_psql_to_rds_command" {
  description = "오케스트레이터에서 RDS 접속 명령어 (오케스트레이터 내부에서 실행)"
  value       = "psql -h ${aws_db_instance.target.address} -p ${aws_db_instance.target.port} -U ${var.db_username} -d ${var.db_name}"
}

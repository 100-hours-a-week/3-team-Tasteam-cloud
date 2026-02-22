output "endpoint" {
  description = "RDS 엔드포인트 (host:port)"
  value       = aws_db_instance.main.endpoint
}

output "address" {
  description = "RDS 호스트명"
  value       = aws_db_instance.main.address
}

output "port" {
  description = "RDS 포트"
  value       = aws_db_instance.main.port
}

output "identifier" {
  description = "RDS 인스턴스 식별자"
  value       = aws_db_instance.main.identifier
}

output "username" {
  description = "마스터 유저 이름"
  value       = aws_db_instance.main.username
}

output "password" {
  description = "마스터 유저 비밀번호 (자동 생성)"
  value       = random_password.master.result
  sensitive   = true
}

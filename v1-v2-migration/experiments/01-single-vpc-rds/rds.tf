# RDS 서브넷 그룹 (최소 2 AZ 필요)
resource "aws_db_subnet_group" "target" {
  name = "migration-exp-db-subnet-group"
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id,
  ]

  tags = {
    Name        = "migration-exp-db-subnet-group"
    Environment = var.environment
  }
}

# RDS 파라미터 그룹 — Logical Replication 지원
resource "aws_db_parameter_group" "target" {
  family = "postgres17"
  name   = "migration-exp-pg-params"

  # CDC(Logical Replication) 수신을 위한 설정
  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = {
    Name        = "migration-exp-pg-params"
    Environment = var.environment
  }
}

# 타겟 RDS PostgreSQL
resource "aws_db_instance" "target" {
  identifier     = "migration-exp-target-rds"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.target.name
  vpc_security_group_ids = [aws_security_group.target_rds.id]
  parameter_group_name   = aws_db_parameter_group.target.name

  # Single-AZ (실험용)
  multi_az = false

  # 실험이므로 최종 스냅샷 스킵
  skip_final_snapshot = true

  # 퍼블릭 접근 불가 (EC2를 통해서만 접근)
  publicly_accessible = false

  tags = {
    Name        = "migration-exp-target-rds"
    Environment = var.environment
  }
}

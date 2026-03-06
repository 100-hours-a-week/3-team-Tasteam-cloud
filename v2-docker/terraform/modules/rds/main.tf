# ──────────────────────────────────────────────
# DB Parameter Group — Logical Replication 활성화
# ──────────────────────────────────────────────

resource "aws_db_parameter_group" "main" {
  family = "postgres${var.engine_version}"
  name   = "${var.environment}-db-params-main"

  # CDC(Logical Replication) 수신을 위한 설정
  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  # ── 로깅 설정 ──
  # - 전체 쿼리 로깅 OFF, 슬로우 쿼리만 기록
  parameter {
    name  = "log_statement"
    value = "none"
  }

  # - N ms 이상 슬로우 쿼리 기록 (-1: 비활성화)
  parameter {
    name  = "log_min_duration_statement"
    value = var.log_min_duration_statement
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  # - 데드락 감지 대기 이후 lock wait 기록
  parameter {
    name  = "log_lock_waits"
    value = "1"
  }

  # - 모든 임시 파일 사용 기록 (0 = 전부)
  parameter {
    name  = "log_temp_files"
    value = "0"
  }

  # - 250ms 이상 autovacuum 기록
  parameter {
    name  = "log_autovacuum_min_duration"
    value = "250"
  }

  tags = {
    Name = "${var.environment}-db-params-main"
  }
}

# ──────────────────────────────────────────────
# DB Subnet Group — Private 서브넷 묶음
# ──────────────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name       = "${var.environment}-db-subnet-group-main"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.environment}-db-subnet-group-main"
  }
}

# ──────────────────────────────────────────────
# Master Password — 자동 생성
# ──────────────────────────────────────────────

resource "random_password" "master" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()-_=+"
}

# ──────────────────────────────────────────────
# RDS PostgreSQL Instance
# ──────────────────────────────────────────────

resource "aws_db_instance" "main" {
  identifier     = "${var.environment}-tasteam-main"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"

  db_name  = var.db_name
  username = var.username
  password = random_password.master.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = var.security_group_ids
  parameter_group_name   = aws_db_parameter_group.main.name

  multi_az            = var.multi_az
  publicly_accessible = false

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.environment}-tasteam-main-final"

  # CloudWatch Logs export (postgresql 로그)
  enabled_cloudwatch_logs_exports = var.enable_log_exports ? ["postgresql"] : []

  tags = {
    Name = "${var.environment}-rds-main"
  }
}

# --- EC2 (소스) 보안 그룹 ---

resource "aws_security_group" "source_ec2" {
  description = "Migration experiment - source EC2"
  name        = "migration-exp-sg-source-ec2"
  vpc_id      = aws_vpc.experiment.id

  # SSH 접속
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
  }

  # 모든 아웃바운드
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  tags = {
    Name        = "migration-exp-sg-source-ec2"
    Environment = var.environment
  }
}

# --- EC2 (오케스트레이터) 보안 그룹 ---

resource "aws_security_group" "orchestrator" {
  description = "Migration experiment - orchestrator EC2"
  name        = "migration-exp-sg-orchestrator"
  vpc_id      = aws_vpc.experiment.id

  # SSH 접속
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
  }

  # 모든 아웃바운드
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  tags = {
    Name        = "migration-exp-sg-orchestrator"
    Environment = var.environment
  }
}

# --- RDS (타겟) 보안 그룹 ---

resource "aws_security_group" "target_rds" {
  description = "Migration experiment - target RDS (access from EC2 only)"
  name        = "migration-exp-sg-target-rds"
  vpc_id      = aws_vpc.experiment.id

  # EC2 소스에서 PostgreSQL 접속 허용
  ingress {
    security_groups = [aws_security_group.source_ec2.id]
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    description     = "PostgreSQL from source EC2"
  }

  # 오케스트레이터에서 PostgreSQL 접속 허용
  ingress {
    security_groups = [aws_security_group.orchestrator.id]
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    description     = "PostgreSQL from orchestrator EC2"
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  tags = {
    Name        = "migration-exp-sg-target-rds"
    Environment = var.environment
  }
}

# --- 별도 보안 그룹 규칙 (순환 참조 방지) ---

# RDS → source EC2 방향 PostgreSQL 인바운드
resource "aws_security_group_rule" "source_ec2_from_rds" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  description              = "PostgreSQL from RDS"
  security_group_id        = aws_security_group.source_ec2.id
  source_security_group_id = aws_security_group.target_rds.id
}

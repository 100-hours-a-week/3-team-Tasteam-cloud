# ──────────────────────────────────────────────
# App Security Group — EC2 앱 서버용
# ──────────────────────────────────────────────

resource "aws_security_group" "app" {
  description = "Security group for application server"
  name        = "${var.environment}-sg-app"
  vpc_id      = var.vpc_id

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    description = "SSH"
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    description = "HTTP"
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    description = "HTTPS"
  }

  tags = {
    Name = "${var.environment}-sg-app"
  }
}

# ──────────────────────────────────────────────
# RDS Security Group — PostgreSQL용
# ──────────────────────────────────────────────

resource "aws_security_group" "rds" {
  description = "Security group for RDS PostgreSQL"
  name        = "${var.environment}-sg-rds"
  vpc_id      = var.vpc_id

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  ingress {
    security_groups = [aws_security_group.app.id]
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    description     = "PostgreSQL from app server only"
  }

  tags = {
    Name = "${var.environment}-sg-rds"
  }
}

# ──────────────────────────────────────────────
# Redis Security Group — Redis 인스턴스용
# ──────────────────────────────────────────────

resource "aws_security_group" "redis" {
  description = "Security group for Redis instance"
  name        = "${var.environment}-sg-redis"
  vpc_id      = var.vpc_id

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    description = "SSH"
  }

  ingress {
    security_groups = [aws_security_group.app.id]
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    description     = "Redis from app server only"
  }

  tags = {
    Name = "${var.environment}-sg-redis"
  }
}

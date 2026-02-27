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

resource "aws_security_group_rule" "app_prometheus_actuator" {
  count = var.shared_vpc_cidr != null ? 1 : 0

  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = [var.shared_vpc_cidr]
  security_group_id = aws_security_group.app.id
  description       = "Prometheus scrape - Spring Actuator (from shared VPC)"
}

resource "aws_security_group_rule" "app_prometheus_alloy" {
  count = var.shared_vpc_cidr != null ? 1 : 0

  type              = "ingress"
  from_port         = 12345
  to_port           = 12345
  protocol          = "tcp"
  cidr_blocks       = [var.shared_vpc_cidr]
  security_group_id = aws_security_group.app.id
  description       = "Prometheus scrape - Alloy metrics (from shared VPC)"
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

  ingress {
    cidr_blocks = var.shared_vpc_cidr != null ? [var.shared_vpc_cidr] : []
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    description = "PostgreSQL from shared monitoring (postgres exporter)"
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

resource "aws_security_group_rule" "redis_prometheus_alloy" {
  count = var.shared_vpc_cidr != null ? 1 : 0

  type              = "ingress"
  from_port         = 12345
  to_port           = 12345
  protocol          = "tcp"
  cidr_blocks       = [var.shared_vpc_cidr]
  security_group_id = aws_security_group.redis.id
  description       = "Prometheus scrape - Alloy metrics (from shared VPC)"
}

# ──────────────────────────────────────────────
# Monitoring Security Group — PLG 스택용
# ──────────────────────────────────────────────

resource "aws_security_group" "monitoring" {
  count = var.enable_monitoring ? 1 : 0

  description = "Security group for monitoring server (PLG stack)"
  name        = "${var.environment}-sg-monitoring"
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
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    description = "Grafana"
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 3100
    to_port     = 3100
    protocol    = "tcp"
    description = "Loki"
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    description = "Prometheus"
  }

  tags = {
    Name = "${var.environment}-sg-monitoring"
  }
}

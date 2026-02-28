# ──────────────────────────────────────────────
# App Security Group — EC2 앱 서버용
# ──────────────────────────────────────────────

resource "aws_security_group" "app" {
  description = "Security group for application server"
  name        = "${var.environment}-sg-app"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.environment}-sg-app"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── App SG: Egress ──

resource "aws_security_group_rule" "app_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.app.id
  description       = "Allow all outbound"
}

# ── App SG: Ingress ──

resource "aws_security_group_rule" "app_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.app.id
  description       = "SSH"
}

resource "aws_security_group_rule" "app_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.app.id
  description       = "HTTP"
}

resource "aws_security_group_rule" "app_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.app.id
  description       = "HTTPS"
}

resource "aws_security_group_rule" "app_spring_self" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.app.id
  source_security_group_id = aws_security_group.app.id
  description              = "Spring backend from app security group (Caddy to Spring)"
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

  tags = {
    Name = "${var.environment}-sg-rds"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── RDS SG: Egress ──

resource "aws_security_group_rule" "rds_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rds.id
  description       = "Allow all outbound"
}

# ── RDS SG: Ingress ──

resource "aws_security_group_rule" "rds_postgres_from_app" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = aws_security_group.app.id
  description              = "PostgreSQL from app server only"
}

resource "aws_security_group_rule" "rds_postgres_from_shared" {
  count = var.shared_vpc_cidr != null ? 1 : 0

  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = [var.shared_vpc_cidr]
  security_group_id = aws_security_group.rds.id
  description       = "PostgreSQL from shared monitoring (postgres exporter)"
}

# ──────────────────────────────────────────────
# Redis Security Group — Redis 인스턴스용
# ──────────────────────────────────────────────

resource "aws_security_group" "redis" {
  description = "Security group for Redis instance"
  name        = "${var.environment}-sg-redis"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.environment}-sg-redis"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Redis SG: Egress ──

resource "aws_security_group_rule" "redis_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.redis.id
  description       = "Allow all outbound"
}

# ── Redis SG: Ingress ──

resource "aws_security_group_rule" "redis_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.redis.id
  description       = "SSH"
}

resource "aws_security_group_rule" "redis_from_app" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redis.id
  source_security_group_id = aws_security_group.app.id
  description              = "Redis from app server only"
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

  tags = {
    Name = "${var.environment}-sg-monitoring"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Monitoring SG: Egress ──

resource "aws_security_group_rule" "monitoring_egress_all" {
  count = var.enable_monitoring ? 1 : 0

  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.monitoring[0].id
  description       = "Allow all outbound"
}

# ── Monitoring SG: Ingress ──

resource "aws_security_group_rule" "monitoring_ssh" {
  count = var.enable_monitoring ? 1 : 0

  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.monitoring[0].id
  description       = "SSH"
}

resource "aws_security_group_rule" "monitoring_grafana" {
  count = var.enable_monitoring ? 1 : 0

  type              = "ingress"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.monitoring[0].id
  description       = "Grafana"
}

resource "aws_security_group_rule" "monitoring_loki" {
  count = var.enable_monitoring ? 1 : 0

  type              = "ingress"
  from_port         = 3100
  to_port           = 3100
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.monitoring[0].id
  description       = "Loki"
}

resource "aws_security_group_rule" "monitoring_prometheus" {
  count = var.enable_monitoring ? 1 : 0

  type              = "ingress"
  from_port         = 9090
  to_port           = 9090
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.monitoring[0].id
  description       = "Prometheus"
}

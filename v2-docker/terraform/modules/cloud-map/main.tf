# ──────────────────────────────────────────────
# Cloud Map — Private DNS Namespace
# internal.tasteam.local 도메인을 VPC 내부에서만 해석
# ──────────────────────────────────────────────

resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = "internal.tasteam.local"
  vpc         = var.vpc_id
  description = "tasteam v2 내부 서비스 디스커버리 네임스페이스"

  tags = {
    Name = "${var.environment}-cloudmap-ns-internal"
  }
}

# ──────────────────────────────────────────────
# Cloud Map — Service
# {service_name}.internal.tasteam.local 로 DNS 조회 가능
# ──────────────────────────────────────────────

resource "aws_service_discovery_service" "this" {
  name = var.service_name

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.this.id
    routing_policy = "MULTIVALUE"  # 다중 IP 반환 (모든 healthy 인스턴스)

    dns_records {
      type = "A"
      ttl  = var.dns_ttl
    }
  }

  tags = {
    Name = "${var.environment}-cloudmap-svc-${var.service_name}"
  }
}

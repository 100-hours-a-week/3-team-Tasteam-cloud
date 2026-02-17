# ──────────────────────────────────────────────
# SSM Parameter Store
# ──────────────────────────────────────────────
# 파라미터 경로: /{env}/tasteam/{service}/{name}
# 값은 Terraform이 아닌 AWS 콘솔/CLI에서 직접 설정.
# lifecycle ignore_changes 로 값 변경을 Terraform이 덮어쓰지 않음.

resource "aws_ssm_parameter" "this" {
  for_each = var.parameters

  name        = "/${var.environment}/tasteam/${each.key}"
  type        = each.value.type
  value       = "PLACEHOLDER"
  description = each.value.description

  tags = {
    Name = "${var.environment}-ssm-${replace(each.key, "/", "-")}"
  }

  lifecycle {
    ignore_changes = [value]
  }
}

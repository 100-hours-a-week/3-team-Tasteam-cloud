# ──────────────────────────────────────────────
# Lifecycle Hook — 인스턴스 시작
# EventBridge default bus에 자동 발행됨 → notification_target_arn 불필요
# ──────────────────────────────────────────────

resource "aws_autoscaling_lifecycle_hook" "launching" {
  count = var.enable_lifecycle_hooks ? 1 : 0

  name                   = "${var.environment}-asg-${var.purpose}-launching"
  autoscaling_group_name = aws_autoscaling_group.this.name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"
  default_result         = "ABANDON"          # Lambda 실패 시 인스턴스 폐기 (안전)
  heartbeat_timeout      = var.lifecycle_hook_timeout
}

# ──────────────────────────────────────────────
# Lifecycle Hook — 인스턴스 종료
# ──────────────────────────────────────────────

resource "aws_autoscaling_lifecycle_hook" "terminating" {
  count = var.enable_lifecycle_hooks ? 1 : 0

  name                   = "${var.environment}-asg-${var.purpose}-terminating"
  autoscaling_group_name = aws_autoscaling_group.this.name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
  default_result         = "CONTINUE"         # Lambda 실패 시 그냥 종료 (좀비 레코드 가능하나 허용)
  heartbeat_timeout      = var.lifecycle_hook_timeout
}

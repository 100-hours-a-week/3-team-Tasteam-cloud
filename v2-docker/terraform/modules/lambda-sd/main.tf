# ──────────────────────────────────────────────
# Lambda — 서비스 디스커버리 핸들러
# ──────────────────────────────────────────────

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/builds/handler.zip"
}

resource "aws_lambda_function" "sd" {
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  function_name    = "${var.environment}-tasteam-lambda-sd-${var.purpose}"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = var.lambda_timeout

  environment {
    variables = {
      CLOUD_MAP_SERVICE_ID = var.cloud_map_service_id
      APP_PORT             = tostring(var.app_port)
    }
  }

  tags = {
    Name = "${var.environment}-lambda-sd-${var.purpose}"
  }
}

# ──────────────────────────────────────────────
# EventBridge Rule — ASG lifecycle 이벤트 필터링
# ASG lifecycle hook 이벤트는 EventBridge default bus에 자동 발행됨
# ──────────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "asg_lifecycle" {
  name        = "${var.environment}-rule-sd-${var.purpose}"
  description = "ASG ${var.asg_name} lifecycle 이벤트 → Lambda 서비스 디스커버리"

  event_pattern = jsonencode({
    source      = ["aws.autoscaling"]
    detail-type = [
      "EC2 Instance-launch Lifecycle Action",
      "EC2 Instance-terminate Lifecycle Action",
    ]
    detail = {
      AutoScalingGroupName = [var.asg_name]
    }
  })

  tags = {
    Name = "${var.environment}-rule-sd-${var.purpose}"
  }
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.asg_lifecycle.name
  target_id = "LambdaServiceDiscovery"
  arn       = aws_lambda_function.sd.arn
}

# ──────────────────────────────────────────────
# Lambda Permission — EventBridge 호출 허용
# ──────────────────────────────────────────────

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sd.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.asg_lifecycle.arn
}

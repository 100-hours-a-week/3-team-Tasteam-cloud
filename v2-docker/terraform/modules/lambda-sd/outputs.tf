output "lambda_arn" {
  description = "서비스 디스커버리 Lambda ARN"
  value       = aws_lambda_function.sd.arn
}

output "lambda_function_name" {
  description = "서비스 디스커버리 Lambda 함수 이름"
  value       = aws_lambda_function.sd.function_name
}

output "eventbridge_rule_arn" {
  description = "ASG lifecycle 이벤트 EventBridge Rule ARN"
  value       = aws_cloudwatch_event_rule.asg_lifecycle.arn
}

output "asg_name" {
  description = "Auto Scaling Group 이름"
  value       = aws_autoscaling_group.this.name
}

output "asg_arn" {
  description = "Auto Scaling Group ARN"
  value       = aws_autoscaling_group.this.arn
}

output "launch_template_id" {
  description = "Launch Template ID"
  value       = aws_launch_template.this.id
}

output "iam_role_arn" {
  description = "IAM Role ARN"
  value       = aws_iam_role.this.arn
}

output "iam_role_name" {
  description = "IAM Role name"
  value       = aws_iam_role.this.name
}

output "instance_profile_name" {
  description = "IAM Instance Profile 이름"
  value       = aws_iam_instance_profile.this.name
}

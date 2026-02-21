# ──────────────────────────────────────────────
# IAM Role — Lambda 실행 역할
# ──────────────────────────────────────────────

resource "aws_iam_role" "lambda" {
  name = "${var.environment}-tasteam-lambda-sd-${var.purpose}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# ──────────────────────────────────────────────
# IAM Policy — CloudWatch Logs (Lambda 기본)
# ──────────────────────────────────────────────

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ──────────────────────────────────────────────
# IAM Policy — Cloud Map register/deregister
# ──────────────────────────────────────────────

resource "aws_iam_role_policy" "cloud_map" {
  name = "cloud-map-sd"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "servicediscovery:RegisterInstance",
        "servicediscovery:DeregisterInstance",
        "servicediscovery:UpdateInstanceCustomHealthStatus",
      ]
      Resource = "*"
    }]
  })
}

# ──────────────────────────────────────────────
# IAM Policy — EC2 IP 조회
# ──────────────────────────────────────────────

resource "aws_iam_role_policy" "ec2_describe" {
  name = "ec2-describe"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:DescribeInstances"]
      Resource = "*"
    }]
  })
}

# ──────────────────────────────────────────────
# IAM Policy — ASG lifecycle action 완료 보고
# ──────────────────────────────────────────────

resource "aws_iam_role_policy" "asg_lifecycle" {
  name = "asg-lifecycle"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["autoscaling:CompleteLifecycleAction"]
      Resource = "*"
    }]
  })
}

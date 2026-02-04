resource "aws_iam_user" "readonly" {
  name = "tasteam-readonly"
  path = "/"

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_user_policy_attachment" "readonly" {
  user       = aws_iam_user.readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# 콘솔 접근(비밀번호)은 보안 문제로 인해 AWS 콘솔에서 수동 설정함 (tfstate 저장 방지)

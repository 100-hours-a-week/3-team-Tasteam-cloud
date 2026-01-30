# EC2용 IAM 역할
resource "aws_iam_role" "ec2_s3" {
  name = "ec2-s3-presigned-url-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "ec2-s3-presigned-url-role"
  }
}

# S3 Presigned URL 생성에 필요한 정책
resource "aws_iam_role_policy" "s3_presigned_url" {
  name = "s3-presigned-url-policy"
  role = aws_iam_role.ec2_s3.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.uploads.arn}/*"
      }
    ]
  })
}

# EC2 인스턴스 프로파일
# 주의: 인스턴스당 프로파일은 하나만 연결 가능
# 권한 추가 시 이 역할에 새 aws_iam_role_policy를 붙이면 됨
resource "aws_iam_instance_profile" "ec2_s3" {
  name = "ec2-s3-instance-profile"
  role = aws_iam_role.ec2_s3.name
}

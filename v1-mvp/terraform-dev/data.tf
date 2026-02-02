# 기존 IAM Role 참조 (Production과 공유)
# MVP 단계에서는 IAM Role 공유가 적절함
# 나중에 분리가 필요하면 이 파일을 수정하고 iam.tf를 추가하면 됨
data "aws_iam_instance_profile" "shared" {
  name = "ec2-s3-instance-profile"
}

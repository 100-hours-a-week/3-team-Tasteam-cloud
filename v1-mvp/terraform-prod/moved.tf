# EC2 인스턴스 리소스 이름 변경
# dev_single_instance -> prod_single_instance
moved {
  from = aws_instance.dev_single_instance
  to   = aws_instance.prod_single_instance
}

resource "aws_instance" "dev_single_instance" {
  ami                         = var.instance_ami
  associate_public_ip_address = true
  availability_zone           = var.availability_zone
  ebs_optimized               = true
  instance_type               = var.instance_type
  key_name                    = var.key_name
  private_ip                  = "172.31.29.122"
  subnet_id                   = aws_subnet.public_b.id

  tags = {
    Name = var.instance_name
  }

  vpc_security_group_ids = [aws_security_group.main.id]

  metadata_options {
    # Docker 컨테이너에서 IMDS 접근을 위해 hop limit을 2로 설정 (기본값 1로 하면 차단됨)
    http_put_response_hop_limit = 2
    # 보안 강화를 위해 IMDSv2(토큰 기반 인증) 강제
    http_tokens = "required"
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }
}

resource "aws_eip" "main" {
  domain = "vpc"
}

resource "aws_eip_association" "main" {
  instance_id   = aws_instance.dev_single_instance.id
  allocation_id = aws_eip.main.id
}

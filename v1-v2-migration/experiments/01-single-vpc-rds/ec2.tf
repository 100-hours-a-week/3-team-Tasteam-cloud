# 소스 EC2 — prod AMI 스냅샷을 그대로 사용
resource "aws_instance" "source" {
  ami                         = var.source_ami
  instance_type               = var.source_instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.source_ec2.id]

  tags = {
    Name        = "migration-exp-ec2-source"
    Environment = var.environment
  }

  metadata_options {
    http_put_response_hop_limit = 2
    http_tokens                 = "required"
  }

  root_block_device {
    volume_size = 40
    volume_type = "gp3"
  }
}

# SSH 접속용 EIP
resource "aws_eip" "source" {
  domain = "vpc"

  tags = {
    Name        = "migration-exp-eip-source"
    Environment = var.environment
  }
}

resource "aws_eip_association" "source" {
  instance_id   = aws_instance.source.id
  allocation_id = aws_eip.source.id
}

# ============================================================
# 마이그레이션 오케스트레이터 EC2 — Ubuntu 22.04 + Docker
# ============================================================

# 최신 Ubuntu 22.04 LTS AMI 자동 조회 (Canonical 공식)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "orchestrator" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.orchestrator_instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.orchestrator.id]

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail

    # Docker 공식 설치
    apt-get update
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io \
      docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    usermod -aG docker ubuntu

    # PostgreSQL 클라이언트 (pg_dump/pg_restore 용)
    apt-get install -y postgresql-client
  EOF

  tags = {
    Name        = "migration-exp-ec2-orchestrator"
    Environment = var.environment
  }

  metadata_options {
    http_put_response_hop_limit = 2
    http_tokens                 = "required"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }
}

# 오케스트레이터 SSH 접속용 EIP
resource "aws_eip" "orchestrator" {
  domain = "vpc"

  tags = {
    Name        = "migration-exp-eip-orchestrator"
    Environment = var.environment
  }
}

resource "aws_eip_association" "orchestrator" {
  instance_id   = aws_instance.orchestrator.id
  allocation_id = aws_eip.orchestrator.id
}

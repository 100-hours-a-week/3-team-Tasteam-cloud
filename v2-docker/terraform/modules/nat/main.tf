# ──────────────────────────────────────────────
# Security Group — NAT 인스턴스용
# ──────────────────────────────────────────────

resource "aws_security_group" "nat" {
  description = "Security group for NAT instance"
  name        = "${var.environment}-sg-nat"
  vpc_id      = var.vpc_id

  # VPC 내부에서 들어오는 모든 트래픽 허용
  ingress {
    cidr_blocks = [var.vpc_cidr]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    description = "Allow all inbound from VPC CIDR"
  }

  # 외부로 나가는 모든 트래픽 허용 (NAT 역할 수행)
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    description = "Allow all outbound"
  }

  tags = {
    Name = "${var.environment}-sg-nat"
  }
}

# ──────────────────────────────────────────────
# EC2 Instance — fck-nat AMI
# ──────────────────────────────────────────────

resource "aws_instance" "nat" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.nat.id]
  key_name                    = var.key_name
  source_dest_check           = false
  associate_public_ip_address = false

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "${var.environment}-ec2-nat"
  }
}

# ──────────────────────────────────────────────
# Elastic IP — NAT 인스턴스 고정 공인 IP
# ──────────────────────────────────────────────

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.environment}-eip-nat"
  }
}

resource "aws_eip_association" "nat" {
  instance_id   = aws_instance.nat.id
  allocation_id = aws_eip.nat.id
}

# ──────────────────────────────────────────────
# Route — Private 서브넷 → NAT 인스턴스
# ──────────────────────────────────────────────

resource "aws_route" "private_to_nat" {
  route_table_id         = var.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

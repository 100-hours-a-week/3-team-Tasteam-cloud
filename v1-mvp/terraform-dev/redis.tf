# Redis용 Ubuntu 22.04 LTS AMI 조회
data "aws_ami" "ubuntu_2204" {
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

# Redis 전용 EC2 인스턴스
resource "aws_instance" "redis" {
  ami                         = data.aws_ami.ubuntu_2204.id
  associate_public_ip_address = true
  availability_zone           = var.availability_zone
  instance_type               = "t3.small"
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public_b.id
  iam_instance_profile        = data.aws_iam_instance_profile.shared.name

  tags = {
    Name        = "development-ec2-redis"
    Environment = var.environment
  }

  vpc_security_group_ids = [aws_security_group.redis.id]

  metadata_options {
    http_put_response_hop_limit = 2
    http_tokens                 = "required"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }
}

# Redis 전용 보안 그룹
resource "aws_security_group" "redis" {
  description = "Security group for Redis instance"
  name        = "development-sg-redis"
  vpc_id      = aws_vpc.main.id

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
  }

  ingress {
    cidr_blocks = ["10.0.0.0/16"]
    description = "Redis access from VPC"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
  }

  tags = {
    Name        = "development-sg-redis"
    Environment = var.environment
  }
}

# Redis 인스턴스용 EIP
resource "aws_eip" "redis" {
  domain = "vpc"

  tags = {
    Name        = "development-eip-redis"
    Environment = var.environment
  }
}

resource "aws_eip_association" "redis" {
  instance_id   = aws_instance.redis.id
  allocation_id = aws_eip.redis.id
}

# 실험용 VPC — v1(10.0.0.0/16)과 CIDR 충돌 방지
resource "aws_vpc" "experiment" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "migration-exp-vpc"
    Environment = var.environment
  }
}

# --- Public Subnet (EC2 소스) ---

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.experiment.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "ap-northeast-2b"
  map_public_ip_on_launch = true

  tags = {
    Name        = "migration-exp-subnet-public"
    Environment = var.environment
  }
}

# --- Private Subnets (RDS 서브넷 그룹용, 최소 2 AZ 필요) ---

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.experiment.id
  cidr_block        = "10.1.10.0/24"
  availability_zone = "ap-northeast-2b"

  tags = {
    Name        = "migration-exp-subnet-private-a"
    Environment = var.environment
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.experiment.id
  cidr_block        = "10.1.11.0/24"
  availability_zone = "ap-northeast-2d"

  tags = {
    Name        = "migration-exp-subnet-private-b"
    Environment = var.environment
  }
}

# --- Internet Gateway + Routing ---

resource "aws_internet_gateway" "experiment" {
  vpc_id = aws_vpc.experiment.id

  tags = {
    Name        = "migration-exp-igw"
    Environment = var.environment
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.experiment.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.experiment.id
  }

  tags = {
    Name        = "migration-exp-rtb-public"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

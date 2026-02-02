# Development 환경용 VPC (Production과 완전 분리)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name        = "development-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public_a" {
  availability_zone       = "ap-northeast-2a"
  cidr_block              = "10.0.0.0/20"
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.main.id

  tags = {
    Name        = "development-subnet-public-a"
    Environment = var.environment
  }
}

resource "aws_subnet" "public_b" {
  availability_zone       = "ap-northeast-2b"
  cidr_block              = "10.0.16.0/20"
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.main.id

  tags = {
    Name        = "development-subnet-public-b"
    Environment = var.environment
  }
}

resource "aws_subnet" "public_c" {
  availability_zone       = "ap-northeast-2c"
  cidr_block              = "10.0.32.0/20"
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.main.id

  tags = {
    Name        = "development-subnet-public-c"
    Environment = var.environment
  }
}

resource "aws_subnet" "public_d" {
  availability_zone       = "ap-northeast-2d"
  cidr_block              = "10.0.48.0/20"
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.main.id

  tags = {
    Name        = "development-subnet-public-d"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "development-igw"
    Environment = var.environment
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "development-rtb-public"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_c" {
  subnet_id      = aws_subnet.public_c.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_d" {
  subnet_id      = aws_subnet.public_d.id
  route_table_id = aws_route_table.public.id
}

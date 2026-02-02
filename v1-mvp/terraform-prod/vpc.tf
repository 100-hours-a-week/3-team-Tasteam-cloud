resource "aws_vpc" "main" {
  cidr_block           = "172.31.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name        = "prod-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public_a" {
  availability_zone       = "ap-northeast-2a"
  cidr_block              = "172.31.0.0/20"
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.main.id
}

resource "aws_subnet" "public_b" {
  availability_zone       = "ap-northeast-2b"
  cidr_block              = "172.31.16.0/20"
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.main.id
}

resource "aws_subnet" "public_c" {
  availability_zone       = "ap-northeast-2c"
  cidr_block              = "172.31.32.0/20"
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.main.id
}

resource "aws_subnet" "public_d" {
  availability_zone       = "ap-northeast-2d"
  cidr_block              = "172.31.48.0/20"
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.main.id
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

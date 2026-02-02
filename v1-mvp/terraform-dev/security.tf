resource "aws_security_group" "main" {
  description = "Development environment security group"
  name        = "development-sg-main"
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
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "temporary"
    from_port   = 8080
    to_port     = 8081
    protocol    = "tcp"
  }

  tags = {
    Name        = "development-sg-main"
    Environment = var.environment
  }
}

resource "aws_security_group" "default" {
  description = "default VPC security group"
  name        = "development-sg-default"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol  = -1
    self      = true
    from_port = 0
    to_port   = 0
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "development-sg-default"
    Environment = var.environment
  }
}

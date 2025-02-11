# ----------------------------------------------------------------------------------------------------
# Prerequisites for SVN pipeline module: networking
# ----------------------------------------------------------------------------------------------------

locals {
  aws_region = "ca-central-1"
}

provider "aws" {
  region = local.aws_region
}

terraform {
  backend "local" {
    path = "../tf_state/vpc/terraform.tfstate"
  }
}

resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "main"
  }
}

resource "aws_subnet" "subnet1" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ca-central-1a"

  tags = {
    Name = "private_subnet1"
  }
}

resource "aws_subnet" "subnet2" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ca-central-1b"

  tags = {
    Name = "private_subnet2"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.vpc.id
  service_name = "com.amazonaws.${local.aws_region}.s3"
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id            = aws_vpc.vpc.id
  service_name      = "com.amazonaws.${local.aws_region}.logs"
  subnet_ids        = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    aws_security_group.logs.id
  ]

  private_dns_enabled = false
}

resource "aws_security_group" "logs" {
  name   = "logs-vpc-endpoint-sg"
  vpc_id = aws_vpc.vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic."
  }
}

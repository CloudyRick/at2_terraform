terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
  backend "s3" {
    key    = "PROD/networking.tfstate"
    bucket = "at2-ecs-fargate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  public_subnet_keys = keys(var.public_subnets)
}

# Data Source for AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Local values
locals {
  internet = "0.0.0.0/0"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "gc-main-vpc"
    Env  = "gc"
  }
}

# Public Subnets (for ALB)
resource "aws_subnet" "public" {
  for_each = var.public_subnets
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 4, each.value)
  availability_zone = each.key

  tags = {
    Name = "gc-public-subnet-${each.value}"
    Tier = "Public"
  }
}

# Private Subnets (for ECS)
resource "aws_subnet" "private" {
  for_each = var.private_subnets
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 4, each.value)
  availability_zone = each.key

  tags = {
    Name = "gc-private-subnet-${each.value}"
    Tier = "Private"
  }
}

# Isolated Subnets (for RDS)
resource "aws_subnet" "isolated" {
  for_each = var.isolated_subnets
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 4, each.value)
  availability_zone = each.key

  tags = {
    Name = "gc-isolated-subnet-${each.value}"
    Tier = "Isolated"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "gc-igw"
  }
}

# EIP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.gw]

  tags = {
    Name = "gc-nat-eip"
  }
}

# NAT Gateway (for private subnet internet access)
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id = aws_subnet.public[local.public_subnet_keys[0]].id
  depends_on    = [aws_internet_gateway.gw]

  tags = {
    Name = "gc-nat"
  }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = local.internet
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "gc-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = local.internet
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "gc-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# Isolated Route Table (no internet)
resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "gc-isolated-rt-modified"
  }
}

resource "aws_route_table_association" "isolated" {
  for_each = aws_subnet.isolated
  subnet_id      = each.value.id
  route_table_id = aws_route_table.isolated.id
}





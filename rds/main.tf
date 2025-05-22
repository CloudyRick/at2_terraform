terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
    }
  }
  backend s3 {
        key="PROD/RDS.tfstate"
        bucket="at2-ecs-fargate"
        region="us-east-1"
  }
}




provider "aws" {
  region = "us-east-1"
}

# Data Sources
data "aws_vpc" "selected" {
  filter {
    name   = "tag:Name"
    values = ["gc-main-vpc"]
  }
}

data "aws_subnets" "isolated" {
  filter {
    name   = "tag:Tier"
    values = ["Isolated"]
  }

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
}

data "aws_subnets" "public_subnets" {
  filter {
    name   = "tag:Tier"
    values = ["Public"]
  }
}

# Security Group for RDS
resource "aws_security_group" "gc_rds_sg" {
  name        = "gc-rds-sg"
  description = "Allow MySQL traffic from inside the VPC"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    description = "MySQL from VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "gc-rds-sg"
  }
}

# Subnet Group for RDS
resource "aws_db_subnet_group" "gc_rds_subnet_group" {
  name       = "gc-rds-subnet-group"
  subnet_ids = data.aws_subnets.isolated.ids

  tags = {
    Name = "gc-rds-subnet-group"
  }
}

# Parameter Group (optional)
resource "aws_db_parameter_group" "gc_rds_pg" {
  name   = "gc-mysql57-pg"
  family = "mysql5.7"

  parameter {
    name  = "character_set_server"
    value = "utf8"
  }

  parameter {
    name  = "character_set_client"
    value = "utf8"
  }

  tags = {
    Name = "gc-mysql57-pg"
  }
}

# RDS Instance
resource "aws_db_instance" "gc_mysql" {
  identifier              = "gc-mysql"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  username                = var.db_username
  password                = var.db_password
  db_name                 = var.db_name
  allocated_storage       = 20
  max_allocated_storage   = 100
  db_subnet_group_name    = aws_db_subnet_group.gc_rds_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.gc_rds_sg.id]
  parameter_group_name    = aws_db_parameter_group.gc_rds_pg.name
  availability_zone       = "us-east-1a"
  skip_final_snapshot     = true
  publicly_accessible     = false
  auto_minor_version_upgrade = false
  multi_az                = false

  backup_retention_period = 7
  backup_window           = "02:00-03:00"
  maintenance_window      = "Sun:03:00-Sun:04:00"

  tags = {
    Name = "gc-rds-mysql"
  }
}


## Security Group for Bastion EC2 (SSH only)
resource "aws_security_group" "bastion_sg" {
  name        = "gc-bastion-sg"
  description = "Allow SSH from anywhere (for temporary use)"
  vpc_id      = data.aws_vpc.vpc_id.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Consider narrowing this to your IP only for security
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "gc-bastion-sg"
  }
}


## Launch Bastion EC2
resource "aws_instance" "bastion" {
  ami                    = "ami-0c101f26f147fa7fd" # Amazon Linux 2 AMI (us-east-1, ARM64)
  instance_type          = "t4g.micro"
  subnet_id              = data.aws_subnets.public_subnets.ids[0]
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true
  iam_instance_profile   = "LabRole"  # Make sure LabRole is attached to this profile

  tags = {
    Name = "gc-bastion"
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y mysql
              EOF
}


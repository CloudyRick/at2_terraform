terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
    }
  }

  backend "s3" {
    key    = "PROD/ecs.tfstate"
    bucket = "at2-ecs-fargate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

# DATA SOURCES
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["gc-main-vpc"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "tag:Tier"
    values = ["Public"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "tag:Tier"
    values = ["Private"]
  }
}

# LOCALS
locals {
  all_ips_ipv4   = ["0.0.0.0/0"]
  all_ips_ipv6   = ["::/0"]
  tcp_protocol   = "tcp"
  any_port       = 0
  any_protocol   = "-1"
}

# ECS CLUSTER
resource "aws_ecs_cluster" "main" {
  name = var.ecs_cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# SECURITY GROUPS

resource "aws_security_group" "alb_sg" {
  name        = "gc-alb-sg"
  description = "Allow HTTP from internet"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = local.tcp_protocol
    cidr_blocks = local.all_ips_ipv4
  }

  egress {
    from_port        = local.any_port
    to_port          = local.any_port
    protocol         = local.any_protocol
    cidr_blocks      = local.all_ips_ipv4
    ipv6_cidr_blocks = local.all_ips_ipv6
  }
}

resource "aws_security_group" "ecs_sg" {
  name        = "gc-ecs-fargate-sg"
  description = "Allow HTTP from ALB"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port        = local.any_port
    to_port          = local.any_port
    protocol         = local.any_protocol
    cidr_blocks      = local.all_ips_ipv4
    ipv6_cidr_blocks = local.all_ips_ipv6
  }
}

data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.task_family}"
  retention_in_days = 7
}


# TASK DEFINITION
resource "aws_ecs_task_definition" "app" {
  family                   = var.task_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = data.aws_iam_role.lab_role.arn
  task_role_arn            = data.aws_iam_role.lab_role.arn

  container_definitions = jsonencode([
    {
      name      = var.container_name
      image     = var.container_image
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ],
      environment = [
        {
            name  = "DB_HOST"
            value = var.db_host
        },
        {
            name  = "DB_USER"
            value = var.db_user
        },
        {
            name  = "DB_PASS"
            value = var.db_pass
        },
        {
            name  = "DB_NAME"
            value = var.db_name
        }
      ],
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = "/ecs/${var.task_family}"
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
}


# LOAD BALANCER
resource "aws_lb" "main" {
  name               = var.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.public.ids
}

resource "aws_lb_target_group" "app_tg" {
  name     = var.target_group_name
  port     = 80
  protocol = "HTTP"
  target_type = "ip"
  vpc_id   = data.aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# ECS SERVICE
resource "aws_ecs_service" "app" {
  name            = var.service_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  scheduling_strategy = "REPLICA"
  enable_execute_command = true

  network_configuration {
    subnets         = data.aws_subnets.private.ids
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_tg.arn
    container_name   = var.container_name
    container_port   = 80
  }

  depends_on = [aws_lb_listener.http]
}

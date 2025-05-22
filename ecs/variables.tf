variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default = "gc-container-cluster"
}

variable "task_family" {
  description = "Family name for the ECS task definition"
  type        = string
  default = "gc-task-family"
}

variable "task_cpu" {
  description = "CPU units for the ECS task"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Memory (in MiB) for the ECS task"
  type        = string
  default     = "512"
}

variable "container_name" {
  description = "Name of the container"
  type        = string
  default = "gorgeous-cupcake-php"
}

variable "container_image" {
  description = "Container image URL"
  type        = string
  default = "095714079515.dkr.ecr.us-east-1.amazonaws.com/my-php-app"
}

variable "alb_name" {
  description = "Name of the Application Load Balancer"
  type        = string
  default = "gc-alb"
}

variable "target_group_name" {
  description = "Name of the target group for the ALB"
  type        = string
  default = "gc-container-alb"
}

variable "service_name" {
  description = "Name of the ECS service"
  type        = string
  default = "gc-ecs-service"
}

variable "desired_count" {
  description = "Number of desired ECS tasks"
  type        = number
  default     = 1
}

variable "execution_role" {
  description = "ARN of the IAM role that the ECS task can assume to pull container images and publish logs"
  type        = string
  default = "LabRole"
}

variable "task_role" {
  description = "ARN of the IAM role for the ECS task to assume"
  type        = string
  default = "LabRole"
}

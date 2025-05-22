variable "vpc_cidr_block" {
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  default = {
    "us-east-1a" = 1
    "us-east-1b" = 2
  }
}

variable "private_subnets" {
  default = {
    "us-east-1a" = 3
    "us-east-1b" = 4
  }
}

variable "isolated_subnets" {
  default = {
    "us-east-1a" = 5
    "us-east-1b" = 6
  }
}

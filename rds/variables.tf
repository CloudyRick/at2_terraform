variable "db_username" {
  description = "DB master username"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "DB master password"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "gorgeous_cupcakes"
}

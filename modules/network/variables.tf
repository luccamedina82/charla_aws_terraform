variable "name_prefix" {
  description = "Prefijo de nombrado, calculado una sola vez en el root (local.name_prefix)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_a_subnet_cidr" {
  description = "CIDR block de la subnet pública en la primera AZ"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_b_subnet_cidr" {
  description = "CIDR block de la subnet pública en la segunda AZ"
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_a_subnet_cidr" {
  description = "CIDR block de la subnet privada en la primera AZ"
  type        = string
  default     = "10.0.3.0/24"
}

variable "private_b_subnet_cidr" {
  description = "CIDR block de la subnet privada en la segunda AZ"
  type        = string
  default     = "10.0.4.0/24"
}

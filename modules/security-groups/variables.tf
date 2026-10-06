variable "name_prefix" {
  description = "Prefijo de nombrado, calculado una sola vez en el root (local.name_prefix)"
  type        = string
}

variable "vpc_id" {
  description = "ID de la VPC donde crear los security groups"
  type        = string
}

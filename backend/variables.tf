variable "aws_region" {
  description = "Región de AWS donde se crea el bucket de state"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Perfil de AWS CLI a usar. null = toma AWS_PROFILE del entorno"
  type        = string
  default     = null
}

variable "bucket_prefix" {
  description = "Prefijo del bucket de state; se le sufija el account ID para hacerlo único a nivel global"
  type        = string
  default     = "lab3-lc-tfstate"
}

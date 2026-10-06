variable "name_prefix" {
  description = "Prefijo de nombrado, calculado una sola vez en el root (local.name_prefix). Ojo: el ALB y los target groups tienen un limite de 32 caracteres"
  type        = string
}

variable "vpc_id" {
  description = "VPC donde viven los target groups"
  type        = string
}

variable "public_subnet_ids" {
  description = "Subnets publicas donde el ALB pone sus nodos. Una por AZ"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security group del ALB: 80 y 443 desde internet"
  type        = string
}

variable "certificate_arn" {
  description = "Certificado del listener 443. Tiene que venir ya validado (el output del modulo acm sale del recurso de validacion justamente por eso)"
  type        = string
}

variable "target_port" {
  description = "Puerto donde escuchan las tasks. La trivia (Node) corre como usuario sin root en el 8080"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Path del health check. /api/health nunca toca la base a proposito: si consultara MySQL, una caida de la base marcaria las tasks del frontend como unhealthy y ECS las mataria, convirtiendo una falla parcial en un outage total"
  type        = string
  default     = "/api/health"
}

variable "deregistration_delay" {
  description = "Segundos que el target group espera antes de dar de baja un target. El default de AWS son 300, una eternidad para un deployment de lab"
  type        = number
  default     = 30
}

variable "ssl_policy" {
  description = "Politica TLS del listener 443"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "enable_deletion_protection" {
  description = "Protege el ALB de un delete accidental. Va en false porque la Fase 9 hace un destroy completo"
  type        = bool
  default     = false
}

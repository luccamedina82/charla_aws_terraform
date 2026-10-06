variable "domain_name" {
  description = "FQDN que va a certificar. Tiene que estar dentro de la hosted zone, o la validación DNS nunca resuelve"
  type        = string
}

variable "hosted_zone_id" {
  description = "Hosted zone de Route 53 donde escribir los registros CNAME de validación"
  type        = string
}

variable "subject_alternative_names" {
  description = "Nombres adicionales que cubre el mismo certificado. Cada uno agrega su propio registro de validación"
  type        = list(string)
  default     = []
}

variable "validation_timeout" {
  description = "Cuánto espera el apply a que ACM emita el certificado. La validación DNS suele tardar unos minutos"
  type        = string
  default     = "10m"
}

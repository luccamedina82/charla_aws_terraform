variable "name_prefix" {
  type        = string
  description = "Prefijo de nombres del proyecto (local.name_prefix, ej. lab3-lc-dev)."
}

variable "subscription_emails" {
  type        = list(string)
  description = "Emails suscriptos al topic. Cada uno recibe un mail de confirmación de AWS que hay que aceptar a mano antes de que el topic les notifique de verdad."
}

variable "allow_codestar_notifications" {
  type        = bool
  default     = true
  description = "Agrega el permiso de publicación al topic para el servicio codestar-notifications.amazonaws.com, que usa la Fase 7 (CodePipeline). Dejarlo en false si este topic se reusa en un contexto donde no aplica."
}

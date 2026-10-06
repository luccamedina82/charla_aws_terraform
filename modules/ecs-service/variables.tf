variable "name" {
  type        = string
  description = "Nombre lógico del servicio (\"mysql\" | \"frontend\"). Se usa para el family de la task, el log group y el nombre en Cloud Map."
}

variable "name_prefix" {
  type        = string
  description = "Prefijo de nombres del proyecto (local.name_prefix, ej. lab3-lc-dev)."
}

variable "cluster_id" {
  type        = string
  description = "ID (o ARN) del cluster ECS, module.ecs_cluster.cluster_id."
}

variable "capacity_provider_name" {
  type        = string
  description = "Capacity provider del cluster, module.ecs_cluster.capacity_provider_name."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets privadas donde corre la task (awsvpc)."
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security groups de la network interface de la task."
}

variable "task_cpu" {
  type        = number
  description = "CPU units a nivel task (no contenedor). Para mysql en este lab: 256."
}

variable "task_memory" {
  type        = number
  description = "Memoria en MB a nivel task. Para mysql en este lab: 512."
}

variable "container_image" {
  type        = string
  description = "Imagen del contenedor. Para mysql, usar el espejo de AWS (public.ecr.aws/docker/library/mysql:8.4) para evitar el límite de pulls de Docker Hub."
}

variable "container_port" {
  type        = number
  description = "Puerto que expone el contenedor (3306 en mysql, 80 en frontend)."
}

variable "desired_count" {
  type        = number
  description = "Cantidad de tasks deseadas (1 en mysql, 2 en frontend)."
}

variable "environment_variables" {
  type = list(object({
    name  = string
    value = string
  }))
  default     = []
  description = "Variables de entorno en claro. Nunca credenciales acá — esas van por secrets."
}

variable "secrets" {
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default     = []
  description = "Secretos inyectados vía bloque secrets + valueFrom (ARN de SSM), nunca por environment."
}

variable "efs_volume" {
  type = object({
    file_system_id  = string
    access_point_id = string
    container_path  = string
  })
  default     = null
  description = "Volumen EFS a montar. null si el servicio no usa EFS (ej. frontend)."
}

variable "service_discovery" {
  type = object({
    namespace_id = string
    dns_ttl      = optional(number, 10)
  })
  default     = null
  description = "Config de Cloud Map. null si el servicio no se registra (ej. frontend, que se descubre vía ALB)."
}

variable "load_balancer" {
  type = object({
    target_group_arn = string
    container_name   = optional(string)
  })
  default     = null
  description = "Config del ALB. null si el servicio no está detrás de un load balancer (ej. mysql)."
}

variable "blue_green" {
  type = object({
    alternate_target_group_arn   = string
    production_listener_rule_arn = string
    role_arn                     = string
    test_listener_rule_arn       = optional(string)
    bake_time_in_minutes         = optional(number)
  })
  default     = null
  description = "Activa el deployment blue/green nativo de ECS. null = rolling con circuit breaker (caso mysql). Los tres primeros campos son obligatorios para AWS: ECS levanta el set nuevo en el target group alterno y despues reescribe la listener rule de produccion, asumiendo el rol indicado."
}

variable "health_check_grace_period_seconds" {
  type        = number
  default     = null
  description = "Segundos que el target group espera antes de empezar a evaluar una task recien creada. Solo valido con load_balancer; en mysql tiene que quedar en null."
}

variable "ordered_placement_strategies" {
  type = list(object({
    type  = string
    field = string
  }))
  default     = []
  description = "Placement strategies del servicio. Vacío en mysql; spread por AZ e instancia en frontend."
}

variable "log_retention_days" {
  type        = number
  default     = 14
  description = "Retención del log group en CloudWatch Logs."
}

variable "enable_execute_command" {
  type        = bool
  default     = true
  description = "Habilita ECS Exec para entrar a la task. Es lo que permite verificar la persistencia de mysql corriendo un SELECT desde adentro (Listo cuando de la Fase 4). Requiere permisos ssmmessages en el rol de TASK, que este módulo agrega solo cuando está en true."
}

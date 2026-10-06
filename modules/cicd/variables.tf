variable "name_prefix" {
  type        = string
  description = "Prefijo de nombres del proyecto (local.name_prefix, ej. lab3-lc-dev)."
}

variable "github_owner" {
  type        = string
  description = "Owner/organización de GitHub del repo de la app (luccamedina82)."
}

variable "github_repo" {
  type        = string
  description = "Nombre del repo de la app (charla_aws_app)."
}

variable "branch" {
  type        = string
  default     = "main"
  description = "Rama que dispara el pipeline."
}

variable "ecr_repository_url" {
  type        = string
  description = "URL del repo ECR (module.ecr.repository_url), para el build arg REPOSITORY_URI de CodeBuild."
}

variable "ecr_repository_arn" {
  type        = string
  description = "ARN del repo ECR, para acotar los permisos de push/pull de CodeBuild."
}

variable "cluster_name" {
  type        = string
  description = "Nombre del cluster ECS (module.ecs_cluster.cluster_name)."
}

variable "frontend_service_name" {
  type        = string
  description = "Nombre del servicio ECS del frontend (module.ecs_service_frontend.service_name)."
}

variable "frontend_execution_role_arn" {
  type        = string
  description = "ARN del rol de execution de la task del frontend (module.ecs_service_frontend.execution_role_arn). CodePipeline necesita iam:PassRole sobre este rol para registrar la revisión nueva de la task definition."
}

variable "frontend_task_role_arn" {
  type        = string
  description = "ARN del rol de task del frontend (module.ecs_service_frontend.task_role_arn). Mismo motivo que frontend_execution_role_arn."
}

variable "container_name" {
  type        = string
  default     = "frontend"
  description = "Nombre del contenedor dentro de la task definition, el que espera imagedefinitions.json."
}

variable "notifications_topic_arn" {
  type        = string
  description = "ARN del topic SNS (module.notifications.topic_arn), para notificar éxito/fallo del pipeline."
}

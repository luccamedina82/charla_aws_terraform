output "service_name" {
  description = "Nombre del servicio ECS."
  value       = aws_ecs_service.this.name
}

output "service_id" {
  description = "ID del servicio ECS (cluster/service)."
  value       = aws_ecs_service.this.id
}

output "task_definition_family" {
  description = "Family de la task definition."
  value       = aws_ecs_task_definition.this.family
}

output "task_definition_arn" {
  description = "ARN de la task definition (revisión con la que se creó el servicio; el pipeline registra revisiones nuevas después)."
  value       = aws_ecs_task_definition.this.arn
}

output "log_group_name" {
  description = "Nombre del log group en CloudWatch."
  value       = aws_cloudwatch_log_group.this.name
}

output "service_discovery_arn" {
  description = "ARN del servicio en Cloud Map, si aplica (null en frontend)."
  value       = try(aws_service_discovery_service.this[0].arn, null)
}

output "execution_role_arn" {
  description = "ARN del rol de execution de esta task. Lo necesita cicd para iam:PassRole."
  value       = aws_iam_role.task_execution.arn
}

output "task_role_arn" {
  description = "ARN del rol de task de esta task. Mismo motivo."
  value       = aws_iam_role.task.arn
}

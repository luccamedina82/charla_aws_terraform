output "cluster_id" {
  description = "ID del cluster ECS"
  value       = aws_ecs_cluster.this.id
}

output "cluster_name" {
  description = "Nombre del cluster. Lo usan los dos servicios y los comandos de verificación (aws ecs describe-clusters)"
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ARN del cluster ECS"
  value       = aws_ecs_cluster.this.arn
}

output "capacity_provider_name" {
  description = "Nombre del capacity provider. Va en el capacity_provider_strategy de cada aws_ecs_service"
  value       = aws_ecs_capacity_provider.this.name
}

output "namespace_id" {
  description = "ID del namespace de Cloud Map. Lo consume el aws_service_discovery_service de MySQL"
  value       = aws_service_discovery_private_dns_namespace.this.id
}

output "namespace_arn" {
  description = "ARN del namespace de Cloud Map"
  value       = aws_service_discovery_private_dns_namespace.this.arn
}

output "namespace_name" {
  description = "Nombre del namespace. Con él el módulo ssm-parameters compone DB_HOST = mysql.<namespace>, que es lo que hace imposible volver a hardcodear una IP"
  value       = aws_service_discovery_private_dns_namespace.this.name
}

output "asg_name" {
  description = "Nombre del Auto Scaling Group. Lo necesitan las alarmas de CPUUtilization de la Fase 8"
  value       = aws_autoscaling_group.this.name
}

output "instance_role_name" {
  description = "Nombre del rol de las instancias, por si hace falta adjuntarle una policy desde otro módulo"
  value       = aws_iam_role.instance.name
}

# Outputs del entorno dev.
#
# Los valores que se verifican a mano en cada fase.

output "vpc_id" {
  description = "ID de la VPC del entorno dev"
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "IDs de las subnets públicas"
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs de las subnets privadas"
  value       = module.network.private_subnet_ids
}

output "ecs_cluster_name" {
  description = "Nombre del cluster ECS, para aws ecs describe-clusters"
  value       = module.ecs_cluster.cluster_name
}

output "ecs_namespace_name" {
  description = "Namespace de Cloud Map. DB_HOST sera mysql.<este valor>"
  value       = module.ecs_cluster.namespace_name
}

output "ecs_asg_name" {
  description = "Nombre del ASG del cluster, para verificar la capacidad registrada"
  value       = module.ecs_cluster.asg_name
}

output "ecr_repository_url" {
  description = "URL del repositorio ECR. Destino del docker push de la imagen bootstrap (docs/runbook.md)"
  value       = module.ecr.repository_url
}

output "ecr_repository_name" {
  description = "Nombre del repositorio ECR, para verificar el tag con aws ecr list-images"
  value       = module.ecr.repository_name
}

output "site_url" {
  description = "URL publica del sitio. Es lo que se entrega junto con el DNS del ALB"
  value       = module.dns.site_url
}

output "alb_dns_name" {
  description = "DNS del ALB, para probar el redirect 301 sin pasar por Route 53"
  value       = module.alb.alb_dns_name
}

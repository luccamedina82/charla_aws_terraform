output "alb_arn" {
  description = "ARN del load balancer"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "DNS del ALB. Lo consume el registro alias de Route 53"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Zone ID del ALB, no el de nuestra hosted zone. Un alias de Route 53 necesita los dos"
  value       = aws_lb.this.zone_id
}

output "alb_arn_suffix" {
  description = "Sufijo del ARN en el formato que piden las metricas de CloudWatch (app/nombre/id). Lo necesitan las alarmas de la Fase 8"
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn" {
  description = "Target group que sirve produccion al arrancar. Va en el bloque load_balancer del servicio ECS"
  value       = aws_lb_target_group.blue.arn
}

output "alternate_target_group_arn" {
  description = "Target group alterno, el que recibe la version verde durante un deployment. Obligatorio para el blue/green nativo"
  value       = aws_lb_target_group.green.arn
}

output "target_group_arn_suffix" {
  description = "Sufijo del target group azul para las metricas de CloudWatch (UnHealthyHostCount, TargetResponseTime)"
  value       = aws_lb_target_group.blue.arn_suffix
}

output "alternate_target_group_arn_suffix" {
  description = "Sufijo del target group verde. Las alarmas necesitan los dos: el blue/green alterna cual tiene targets, y mirar uno solo deja la alarma ciega despues de cada deploy"
  value       = aws_lb_target_group.green.arn_suffix
}

output "production_listener_rule_arn" {
  description = "ARN de la listener rule que ECS reescribe para mover el trafico entre los dos target groups"
  value       = aws_lb_listener_rule.production.arn
}

output "https_listener_arn" {
  description = "ARN del listener 443, por si hace falta colgarle mas reglas"
  value       = aws_lb_listener.https.arn
}

output "load_balancer_role_arn" {
  description = "Rol que ECS asume para reescribir la listener rule. Sin el, el blue/green falla al momento de mover el trafico"
  value       = aws_iam_role.ecs_lb.arn
}

output "alb_sg_id" {
  description = "ID del security group del ALB"
  value       = aws_security_group.alb_sg.id
}

output "frontend_sg_id" {
  description = "ID del security group del frontend"
  value       = aws_security_group.frontend_sg.id
}

output "mysql_sg_id" {
  description = "ID del security group de MySQL"
  value       = aws_security_group.mysql_sg.id
}

output "efs_sg_id" {
  description = "ID del security group de EFS"
  value       = aws_security_group.efs_sg.id
}

output "cluster_sg_id" {
  description = "ID del security group de las instancias del cluster ECS"
  value       = aws_security_group.cluster_sg.id
}

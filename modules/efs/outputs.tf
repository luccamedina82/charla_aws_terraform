output "file_system_id" {
  description = "ID del EFS file system, consumido por ecs-service para el volumen de mysql."
  value       = aws_efs_file_system.this.id

  # Sin este depends_on, el grafo de dependencias solo ve el file system: el
  # servicio ECS puede crearse antes de que los mount targets esten disponibles
  # y las primeras tasks fallan al montar con "Failed to resolve
  # fs-xxxx.efs.<region>.amazonaws.com", un error que no menciona los mount
  # targets. Pasa de verdad: en el primer apply de la Fase 4 fallaron dos tasks
  # antes de que ECS reintentara con exito.
  depends_on = [aws_efs_mount_target.this]
}

output "access_point_id" {
  description = "ID del access point de mysql, consumido por ecs-service."
  value       = aws_efs_access_point.this.id
}

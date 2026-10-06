output "repository_url" {
  description = "URL del repositorio (<account>.dkr.ecr.<region>.amazonaws.com/<repo>). Base de la referencia de imagen en la task definition y destino del docker push"
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN del repositorio. Lo consume la policy de CodeBuild en la Fase 7 para acotar el permiso de push a este repo"
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "Nombre del repositorio, sin el registry. Lo usa aws ecr list-images y el imagedefinitions.json del pipeline"
  value       = aws_ecr_repository.this.name
}

output "registry_id" {
  description = "ID de la cuenta que hostea el registry. Lo necesita aws ecr get-login-password para el docker login"
  value       = aws_ecr_repository.this.registry_id
}

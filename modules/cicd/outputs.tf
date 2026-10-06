output "connection_arn" {
  description = "ARN de la CodeStar Connection. PENDING hasta que se autorice a mano en la consola."
  value       = aws_codestarconnections_connection.github.arn
}

output "connection_status" {
  description = "Estado de la connection. Confirmar que pasó de PENDING a AVAILABLE antes de esperar que el pipeline dispare solo."
  value       = aws_codestarconnections_connection.github.connection_status
}

output "pipeline_name" {
  description = "Nombre del pipeline."
  value       = aws_codepipeline.this.name
}

output "pipeline_arn" {
  description = "ARN del pipeline."
  value       = aws_codepipeline.this.arn
}

output "codebuild_project_name" {
  description = "Nombre del proyecto CodeBuild."
  value       = aws_codebuild_project.this.name
}

output "artifacts_bucket_name" {
  description = "Bucket de artifacts del pipeline."
  value       = aws_s3_bucket.artifacts.bucket
}

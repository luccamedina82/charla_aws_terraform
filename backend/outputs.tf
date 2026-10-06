output "bucket_name" {
  description = "Nombre del bucket de state. Va en el campo bucket de environments/dev/backend.tf"
  value       = aws_s3_bucket.this.id
}

output "bucket_region" {
  description = "Región del bucket de state. Va en el campo region de environments/dev/backend.tf"
  value       = var.aws_region
}

output "account_id" {
  description = "Account ID de la cuenta donde vive el bucket. Para la sección Estado actual de CLAUDE.md"
  value       = data.aws_caller_identity.current.account_id
}

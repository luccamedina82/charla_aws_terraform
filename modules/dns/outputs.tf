output "fqdn" {
  description = "Nombre completo del registro creado"
  value       = aws_route53_record.this.fqdn
}

output "site_url" {
  description = "URL publica del sitio, para pegar en la entrega"
  value       = "https://${aws_route53_record.this.fqdn}"
}

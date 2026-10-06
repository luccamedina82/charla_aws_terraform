output "certificate_arn" {
  description = "ARN del certificado, tomado del recurso de validación y no del certificado: así todo lo que dependa de este output espera a que el estado sea ISSUED. El listener 443 con un certificado a medio validar falla"
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "domain_name" {
  description = "FQDN certificado"
  value       = aws_acm_certificate.this.domain_name
}

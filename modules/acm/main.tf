# ---------------------------------------------------------------------------
# Certificado ACM con validación DNS.
#
# Va separado de `dns` a propósito. Si el certificado y el registro alias del ALB
# vivieran en el mismo módulo habría un ciclo: `alb` necesita el ARN del
# certificado para el listener 443, y el alias necesita el DNS del ALB. Así la
# cadena queda acm -> alb -> dns, sin ciclo.
#
# El certificado tiene que estar en la misma región que el ALB. Solo CloudFront
# obliga a us-east-1 sí o sí.
# ---------------------------------------------------------------------------

resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names

  # DNS y no EMAIL: la validación por mail necesita que alguien haga clic en un
  # link, y eso no es reproducible.
  validation_method = "DNS"

  tags = {
    Name = var.domain_name
  }

  # Renovar o cambiar un certificado crea el nuevo antes de destruir el viejo:
  # si fuera al revés, el listener 443 se quedaría sin certificado en el medio.
  lifecycle {
    create_before_destroy = true
  }
}

# Un registro CNAME por nombre certificado. ACM los mira para comprobar que
# controlamos el dominio.
resource "aws_route53_record" "validation" {
  for_each = {
    for option in aws_acm_certificate.this.domain_validation_options :
    option.domain_name => {
      name   = option.resource_record_name
      type   = option.resource_record_type
      record = option.resource_record_value
    }
  }

  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60

  # Necesario para la Fase 9: al recrear el certificado desde cero, ACM puede
  # devolver el mismo nombre de registro y sin esto el apply falla porque el
  # registro "ya existe".
  allow_overwrite = true
}

# Este recurso no crea nada en AWS: bloquea el apply hasta que ACM pasa el
# certificado a ISSUED. Es lo que hace que el listener 443 no se cree antes de
# tiempo. Que el apply se quede esperando unos minutos acá es lo normal —
# cortarlo deja el lock huérfano en S3.
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]

  timeouts {
    create = var.validation_timeout
  }
}

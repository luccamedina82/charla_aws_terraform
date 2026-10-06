# ---------------------------------------------------------------------------
# Registro alias apuntando al ALB.
#
# Alias y no CNAME por dos motivos: un CNAME no se puede poner en el apex de un
# dominio, y el alias no cobra por consulta. Además resuelve directo a las IPs
# del balanceador, sin un salto de resolución extra.
#
# El certificado vive en el módulo `acm`, aparte. Si el alias y el certificado
# estuvieran juntos habría un ciclo: `alb` necesita el ARN del certificado y el
# alias necesita el DNS del ALB.
# ---------------------------------------------------------------------------

resource "aws_route53_record" "this" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name    = var.alb_dns_name
    zone_id = var.alb_zone_id

    # Con un solo ALB no hay a quién derivar si está caído, así que evaluar su
    # salud solo agregaría una forma más de que el nombre deje de resolver.
    evaluate_target_health = false
  }
}

# Módulo `acm`

Certificado de ACM validado por DNS, con sus registros de validación en Route 53.

## Por qué no está dentro de `dns`

Habíamos decidido fusionarlos y estaba mal: genera un **ciclo entre módulos**. El
módulo `alb` necesita el ARN del certificado para el listener 443, y el registro alias
necesita el DNS name del ALB. Si el certificado y el alias viven juntos, Terraform corta
con `dependency cycle`.

Separados, la cadena queda lineal:

```
acm ──certificate_arn──▶ alb ──dns_name──▶ dns
```

## Uso

```hcl
module "acm" {
  source = "../../modules/acm"

  domain_name    = var.domain_name
  hosted_zone_id = data.aws_route53_zone.this.zone_id
}
```

## Los tres recursos

| Recurso | Qué hace |
|---|---|
| `aws_acm_certificate.this` | Pide el certificado. Nace en `PENDING_VALIDATION` |
| `aws_route53_record.validation` | Un CNAME por nombre, que es como ACM comprueba que controlamos el dominio |
| `aws_acm_certificate_validation.this` | No crea nada: **bloquea el apply** hasta que el certificado pasa a `ISSUED` |

Ese tercero es el que importa. El `certificate_arn` que expone el módulo sale de él y
no del certificado, así que todo lo que dependa del output espera a que esté emitido.
Un listener 443 creado con un certificado a medio validar falla.

**El apply se queda unos minutos ahí y es normal.** No cortarlo: un apply interrumpido
deja el lock huérfano en S3.

## Detalles

- `validation_method = "DNS"` y no `EMAIL`: la validación por mail necesita que alguien
  haga clic en un link, y eso no es reproducible.
- `allow_overwrite = true` en los registros: al recrear todo desde cero en la Fase 9,
  ACM puede devolver el mismo nombre de registro y sin esto el apply falla porque el
  registro "ya existe".
- `create_before_destroy` en el certificado: al renovarlo, el nuevo existe antes de que
  se borre el viejo, así el listener nunca se queda sin certificado.
- El certificado vive en la **misma región que el ALB**. Solo CloudFront obliga a
  `us-east-1` sí o sí.

## Variables y outputs

| Variable | Tipo | Default |
|---|---|---|
| `domain_name` | `string` | — |
| `hosted_zone_id` | `string` | — |
| `subject_alternative_names` | `list(string)` | `[]` |
| `validation_timeout` | `string` | `"10m"` |

Outputs: `certificate_arn` (ya validado), `domain_name`.

## Lab vs. producción

| Acá | En producción |
|---|---|
| Un solo FQDN | El apex y el wildcard como SANs |
| Certificado por entorno | Uno compartido, o uno por entorno si los dominios difieren |

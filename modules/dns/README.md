# Módulo `dns`

Un registro alias de Route 53 apuntando al ALB.

## Por qué es un módulo aparte del certificado

Habíamos pensado en fusionarlos y no se puede: genera un **ciclo**. El módulo `alb`
necesita el ARN del certificado para el listener 443, y el alias necesita el DNS name
del ALB. Si viven juntos, Terraform corta con `dependency cycle`.

Separados, la cadena queda lineal:

```
acm ──certificate_arn──▶ alb ──dns_name──▶ dns
```

## Uso

```hcl
module "dns" {
  source = "../../modules/dns"

  hosted_zone_id = data.aws_route53_zone.this.zone_id
  domain_name    = var.domain_name
  alb_dns_name   = module.alb.alb_dns_name
  alb_zone_id    = module.alb.alb_zone_id
}
```

## Alias y no CNAME

- Un CNAME no puede existir en el apex de un dominio. Hoy usamos un subdominio y daría
  igual, pero el alias no cierra esa puerta.
- Las consultas a un alias **no se cobran**.
- Resuelve directo a las IPs del balanceador, sin un salto de resolución extra.

El `zone_id` del bloque `alias` **no es el de nuestra hosted zone**: es el de la zona
del ALB, que AWS asigna por región y expone como atributo del balanceador. Confundirlos
es un error clásico y el mensaje no ayuda.

`evaluate_target_health = false` porque con un solo ALB no hay a quién derivar si está
caído: evaluar su salud solo agregaría otra forma de que el nombre deje de resolver.

## Verificación

```bash
Resolve-DnsName charla.tekforge.site -Server 8.8.8.8
curl -I https://charla.tekforge.site
```

## Lab vs. producción

| Acá | En producción |
|---|---|
| Un registro a un ALB | Registros de failover o latency entre regiones |
| `evaluate_target_health = false` | `true`, con un segundo destino al que derivar |
| La hosted zone se toma con un data source | Suele vivir en su propia cuenta de red |

# Módulo `security-groups`

Los cinco security groups del entorno, encadenados: cada capa solo acepta tráfico
de la anterior, nunca de un CIDR.

```
internet ──443/80──▶ alb ──80──▶ frontend ──3306──▶ mysql ──2049──▶ efs
```

Referenciar el SG de origen en vez de un rango de IPs es lo que hace que la cadena
siga siendo correcta aunque cambien las subnets o las IPs de las tasks.

## Los cinco

| SG | Inbound | De dónde |
|---|---|---|
| `alb-sg` | 443, **80** | internet (`0.0.0.0/0`) |
| `frontend-sg` | 80 | `alb-sg` |
| `mysql-sg` | 3306 | `frontend-sg` |
| `efs-sg` | 2049 | `mysql-sg` |
| `cluster-sg` | **ninguno** | — |

El puerto 80 en el ALB existe solo para responder el redirect 301 a HTTPS: nadie
sirve la aplicación por ahí.

**`cluster-sg` sin inbound es a propósito.** Con `awsvpc` cada task recibe su propia
ENI con sus propios security groups, así que el tráfico entra por el SG de la task y
no por el de la instancia que la hospeda. Si alguna vez hace falta abrir algo acá, es
señal de que algo dejó de usar `awsvpc`.

## Uso

```hcl
module "security_groups" {
  source = "../../modules/security-groups"

  name_prefix = local.name_prefix
  vpc_id      = module.network.vpc_id
}
```

## Detalles de implementación

Las reglas son recursos separados (`aws_vpc_security_group_ingress_rule` y
`aws_vpc_security_group_egress_rule`), nunca bloques `ingress`/`egress` embebidos en
el `aws_security_group`. Con reglas inline, Terraform toma como suya la lista completa
y borra cualquier regla que aparezca por fuera; como recursos separados, cada regla
tiene su propio ciclo de vida y su propio diff en el plan.

Los cinco tienen egress abierto. Lo necesitan: las instancias bajan imágenes del ECR y
las tasks resuelven secretos de SSM, todo saliendo por el NAT.

## Variables y outputs

| Variable | Tipo |
|---|---|
| `name_prefix` | `string` |
| `vpc_id` | `string` |

Outputs: `alb_sg_id`, `frontend_sg_id`, `mysql_sg_id`, `efs_sg_id`, `cluster_sg_id`.

## Lab vs. producción

| Acá | En producción |
|---|---|
| Egress abierto en los cinco | Egress acotado por destino, o VPC endpoints para ECR/SSM |
| 443 desde `0.0.0.0/0` | Igual, o detrás de un WAF / CloudFront |

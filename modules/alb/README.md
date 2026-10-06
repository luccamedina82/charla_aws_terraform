# Módulo `alb`

Application Load Balancer con **dos** target groups, listener 80 que redirige a HTTPS,
listener 443 con certificado, y la listener rule que sirve producción.

## Por qué dos target groups y una listener rule

La forma de este módulo la impone el **blue/green nativo de ECS**, no una preferencia
de diseño. Para mover el tráfico, ECS **reescribe una listener rule** — no la default
action del listener. Eso obliga a tres cosas:

1. **Dos target groups.** Uno sirve producción, el otro recibe la versión nueva.
   Cuál es cuál se alterna en cada deploy: `blue` y `green` son etiquetas de posición,
   no de contenido.
2. **Una `aws_lb_listener_rule` explícita** con el forward. Su ARN es lo que consume
   `ecs-service` en `advanced_configuration.production_listener_rule`.
3. **Un rol IAM** que ECS asume para poder tocar el balanceador
   (`AmazonECSInfrastructureRolePolicyForLoadBalancers`). Sin él, el deployment falla
   justo al mover el tráfico — no antes, lo que hace el síntoma más confuso.

La default action del listener 443 devuelve **503 a propósito**. Si el forward viviera
ahí, ECS no tendría qué reescribir. Un 503 en producción significa que la rule
desapareció.

## Uso

```hcl
module "alb" {
  source = "../../modules/alb"

  name_prefix       = local.name_prefix
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  alb_sg_id         = module.security_groups.alb_sg_id
  certificate_arn   = module.acm.certificate_arn
}
```

## Detalles que importan

**`target_type = "ip"`.** Con `awsvpc` cada task tiene su propia ENI y se registra por
IP. Con `"instance"` se registraría un puerto de la EC2, que en `awsvpc` no existe.

**`ignore_changes = [action]` en la listener rule.** Después del primer blue/green, la
rule apunta al target group contrario al que dice el código. Sin esto, cada plan
propondría devolverla a `blue`: drift permanente y, peor, un cambio de tráfico por
afuera del deployment.

**El health check es `/api/health` y no toca la base.** Es deliberado: si consultara
MySQL, una caída de la base marcaría las tasks del frontend como unhealthy y ECS las
mataría, convirtiendo una falla parcial en un outage total.

**`deregistration_delay = 30`.** El default de AWS son 300 segundos, que hace que cada
deployment se sienta colgado.

**Límite de 32 caracteres** en los nombres de ALB y target group. `lab3-lc-dev` son 11
y `-fe-green` son 9 más: 20 de 32.

**El `certificate_arn` tiene que venir ya validado.** El output del módulo `acm` sale
del recurso `aws_acm_certificate_validation` justamente para eso: un listener 443 con
un certificado a medio emitir falla.

## Variables

| Nombre | Tipo | Default |
|---|---|---|
| `name_prefix` | `string` | — |
| `vpc_id` | `string` | — |
| `public_subnet_ids` | `list(string)` | — |
| `alb_sg_id` | `string` | — |
| `certificate_arn` | `string` | — |
| `target_port` | `number` | `8080` |
| `health_check_path` | `string` | `"/api/health"` |
| `deregistration_delay` | `number` | `30` |
| `ssl_policy` | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` |
| `enable_deletion_protection` | `bool` | `false` |

## Outputs

| Nombre | Lo consume |
|---|---|
| `alb_dns_name` / `alb_zone_id` | El registro alias del módulo `dns` |
| `target_group_arn` | `load_balancer.target_group_arn` del servicio |
| `alternate_target_group_arn` | `advanced_configuration` del blue/green |
| `production_listener_rule_arn` | `advanced_configuration` del blue/green |
| `load_balancer_role_arn` | `advanced_configuration` del blue/green |
| `alb_arn_suffix` / `target_group_arn_suffix` | Las alarmas de CloudWatch de la Fase 8 |

## Verificación

```bash
curl -I http://<alb_dns_name>     # 301 hacia https
curl -I https://<fqdn>            # 200, una vez que haya targets

aws elbv2 describe-target-health --target-group-arn <arn> \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State,Target.AvailabilityZone]'
```

Hasta que exista el servicio frontend, los dos target groups van a tener **0 targets** y
`https` va a devolver el 503 de la default action. Es lo esperado.

## Lab vs. producción

| Acá | En producción |
|---|---|
| Sin test listener | Un listener de prueba para validar la versión verde antes de darle tráfico |
| `enable_deletion_protection = false` | `true` |
| Sin WAF | WAF delante, con reglas administradas |
| Sin access logs | Access logs a S3, que es lo primero que se pide en un incidente |

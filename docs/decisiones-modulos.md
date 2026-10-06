# Decisiones de módulos

Por qué cada módulo es propio o de la comunidad, y qué decisión le da la forma que
tiene. Los módulos van en orden de fase.

Lo que **no** está acá: el detalle de implementación de cada uno, que vive en su
`README.md`. Este archivo responde una sola pregunta — *¿por qué lo escribieron ustedes
en vez de usar uno existente?*

---

## network

**Origen**: propio, no `terraform-aws-modules/vpc/aws`.

El módulo de la comunidad trae features que no usamos (múltiples NAT, VPN, flow logs
opcionales, etc.) y para 2 AZs con 1 NAT es más simple mantener el propio y controlar el
nombrado (`lab3-lc-<env>-*`) que mapear todas sus variables.

Trade-off documentado: con 1 solo NAT en `public_a`, el tráfico saliente de `private_b`
cruza de AZ para llegar al NAT — mayor latencia y costo de transferencia inter-AZ,
aceptado por ser un lab.

## security-groups

**Origen**: propio. El módulo es la **cadena**, no los security groups.

```
internet ──443/80──▶ alb ──80──▶ frontend ──3306──▶ mysql ──2049──▶ efs
```

Cada capa referencia al SG anterior por ID, nunca un CIDR: la cadena sigue siendo
correcta aunque cambien las subnets o las IPs de las tasks. Un módulo de la comunidad
parametriza **un** security group, así que reproducir esto serían cinco invocaciones
pasándose IDs entre sí — más cableado en el root que los recursos que ahorra.

Las reglas van como recursos separados (`aws_vpc_security_group_ingress_rule`), nunca
inline: con reglas embebidas Terraform toma como suya la lista completa y borra
cualquier regla que aparezca por fuera.

## ecr

**Origen**: propio. Son tres recursos y el valor está en la **política de ciclo de
vida**, que es específica de este proyecto.

ECR evalúa las reglas por prioridad y cada imagen queda reclamada por la primera que la
identifica. La regla 1 reserva los tags `bootstrap*` para que la catch-all no pueda
expirarlos: sin ella, 10 builds del pipeline dejarían a la **Fase 9** sin imagen con la
que arrancar. Ningún módulo genérico conoce esa restricción, porque nace del orden de
las fases de este entregable, no de ECR.

## ecs-cluster

**Origen**: propio. El límite del módulo es el **ciclo de vida**, no el servicio de AWS:
cluster, launch template, ASG, capacity provider e instance profile se crean, cambian y
destruyen juntos.

El namespace de Cloud Map vive acá y no en `ecs-service` porque es **uno solo para todo
el cluster**: como `ecs-service` se invoca dos veces, adentro la segunda invocación
intentaría crear un namespace duplicado.

El motivo de fondo para escribirlo es que el wizard de la consola resuelve en silencio
cinco cosas que en Terraform son explícitas —`user_data` con `ECS_CLUSTER=`, AMI por
data source, instance profile, los tres recursos del capacity provider y el log group—
y cuando falta alguna el síntoma no señala la causa. Instancias sanas que nunca aparecen
en el cluster es el caso típico.

## efs

**Origen**: propio. Motivo: es la persistencia de mysql, ahí vive la
especificidad de la solución (mount target por AZ, access point con uid/gid
fijo para la imagen oficial de mysql).

## ssm-parameters

**Origen**: propio. Motivo: naming y paths específicos de la app
(`SPEC-APP.md` §2), y la decisión de generar passwords con `random_password`
(opción (a) de `estado-actual.md` §10) en vez de cargarlas a mano.

## ecs-service

**Origen**: propio. Motivo: es el núcleo de la solución — módulo genérico
invocado dos veces (mysql en Fase 4, frontend en Fase 5) resuelto con
variables `object` opcionales y bloques `dynamic`, sin librería de la
comunidad que cubra ese patrón exacto para este caso.

## alb

**Origen**: propio. La forma del módulo la impone el **blue/green nativo de ECS**, no
una preferencia de diseño: ECS mueve el tráfico reescribiendo una `aws_lb_listener_rule`
—no la default action del listener—, así que el módulo tiene que exponer dos target
groups, una rule explícita y un rol IAM que ECS asuma para tocar el balanceador. Ningún
módulo de la comunidad arma esa combinación, y usar uno genérico habría significado
parchearlo desde afuera.

La default action del listener 443 devuelve **503 a propósito**: si el forward viviera
ahí, ECS no tendría qué reescribir.

## acm

**Origen**: propio, y **separado de `dns`**. Habíamos decidido fusionarlos y estaba mal:
genera un ciclo entre módulos. `alb` necesita el ARN del certificado para el listener
443, y el registro alias necesita el DNS name del ALB. Separados, la cadena queda
lineal: `acm → alb → dns`.

Se descartó el módulo de la comunidad porque son tres recursos y el valor está en un
detalle que hay que controlar: el output `certificate_arn` sale de
`aws_acm_certificate_validation` y no del certificado, para que el listener 443 espere a
que esté `ISSUED`.

## dns

**Origen**: propio. Un solo recurso, un alias apuntando al ALB. Alias y no CNAME: un
CNAME no puede vivir en el apex de un dominio y las consultas a un alias no se cobran.

## notifications

**Origen**: propio, y **separado de `cicd`** — que es la decisión que justifica el
módulo.

El topic lo consumen la Fase 7 (CodePipeline vía CodeStar Notifications) y la Fase 8
(alarmas de CloudWatch). Si viviera dentro de `cicd`, la observabilidad dependería del
pipeline sin ninguna razón real, y no se podría aplicar la Fase 8 sin la 7. En la versión
de la charla solo lo consume `cicd`, pero el límite se mantiene para cuando vuelva la
observabilidad.

Son dos recursos y una policy, así que no hay módulo de la comunidad que valga la pena:
lo que aporta el módulo es el límite, no el código. La `aws_sns_topic_policy` que
habilita a `codestar-notifications.amazonaws.com` está acá y no en `cicd` por el mismo
motivo — es del topic, no del pipeline.

## cicd

**Origen**: propio.

El pipeline está atado a decisiones que ya tomamos en otras fases: deploy provider
**ECS** con `imagedefinitions.json` (no `CodeDeployToECS`), CodeBuild con
`privileged_mode` para poder hacer `docker build`, y el `iam:PassRole` acotado a los dos
roles del frontend con la condición `iam:PassedToService = ecs-tasks.amazonaws.com` en
vez de un `"*"`. Un módulo de la comunidad tendría que recibir todo eso por variable, y
a esa altura no queda módulo: queda un envoltorio.

La CodeStar Connection nace en `PENDING` y se autoriza a mano en la consola. Es **la**
excepción al "sin consola" del enunciado, y está documentada como tal en el runbook.

## Módulos que se sacaron para la charla

`github-oidc` (roles para que GitHub Actions corra `plan`/`apply`) y `observability` (alarmas y dashboard sobre las métricas EMF de la app de e-commerce) existían en el lab original. Se sacaron al adaptarlo para la charla: Terraform se corre a mano y la observabilidad queda para otra charla.

---

## Decisiones transversales

| Decisión | Por qué |
|---|---|
| **Blue/green nativo** en vez de rolling | El provider 6.61 ya lo expone en `aws_ecs_service`. Cuesta dos target groups y una listener rule, y a cambio la versión nueva se valida entera antes de recibir tráfico. Verificado en el primer despliegue: ECS colocó las tasks en el target group alterno y reescribió la rule |
| `ignore_changes = [action]` en la listener rule | Después de un blue/green la rule apunta al target group contrario al del código. Sin esto, cada `plan` propondría devolverla — y ese cambio movería el tráfico de producción por fuera del deployment |
| `depends_on` en el output `file_system_id` del EFS | El grafo solo veía el file system: el servicio ECS podía crearse antes que los mount targets. Pasó de verdad, dos tasks murieron con `Failed to resolve fs-xxxx.efs...` |
| Sin `health_check_custom_config` en Cloud Map | Un bloque vacío no se envía a la API (verificado: `HealthCheckCustomConfig` es null en AWS), pero Terraform propone agregarlo en cada plan y, como es inmutable, fuerza el reemplazo del servicio |
| `target_type = "ip"` en los target groups | Con `awsvpc` cada task tiene su propia ENI y se registra por IP. Con `"instance"` se registraría un puerto de la EC2 que en `awsvpc` no existe |

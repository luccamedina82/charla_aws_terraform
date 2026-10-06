# Estado actual del proyecto

**Actualizado**: martes 25/08, con las Fases 0 a 8 aplicadas. El pipeline corre
end-to-end, el dashboard tiene datos reales y `terraform plan` da **No changes**.
Lo único que falta es la Fase 9 (destroy + apply desde cero) y el diagrama.

Este archivo se lee **junto con** `PLAN-FASES.md` y `CONVENCIONES.md`, y en algunos
puntos los **corrige**: ver §7. Si hay contradicción, manda lo que dice acá, porque
sale de infraestructura ya aplicada y verificada.

---

## 1. Coordenadas

| | |
|---|---|
| Cuenta AWS | `104981180500` |
| Región | `us-east-1` |
| Repo IaC | `github.com/ctaddei/teracloud-lab3-terraform` |
| Repo app | `github.com/ctaddei/teracloud-lab3-app` |
| Backend de state | `s3://lab3-lc-tfstate-104981180500`, key `dev/terraform.tfstate`, `use_lockfile = true` |
| Hosted zone | `luccamedina.ownboarding.teratest.net` (`Z0909248Q51XTVKXPOG`) |
| FQDN acordado | `app.luccamedina.ownboarding.teratest.net` |
| Terraform | `>= 1.11.0` · provider `hashicorp/aws ~> 6.0` (lockeado en **6.61.0**) |

---

## 2. Estado por fase

| # | Fase | Estado |
|---|---|---|
| 0 | Backend de estado | ✅ aplicado |
| 1 | Red + security groups | ✅ aplicado |
| 2 | ECR + imagen bootstrap | ✅ aplicado — el tag `bootstrap` está en el repo |
| 3 | Cluster ECS | ✅ aplicado — 3 instancias registradas |
| 4 | EFS + MySQL + SSM | ✅ aplicado y verificado — la persistencia sobrevive a matar la task (§13) |
| 5 | ALB + frontend | ✅ aplicado — 2 tasks `healthy`, una por AZ |
| 6 | DNS + HTTPS | ✅ aplicado — `https://app.luccamedina.ownboarding.teratest.net` → 200 |
| 7 | CI/CD | ✅ aplicado y verificado — pipeline verde end-to-end (§15) |
| 8 | Observabilidad | ✅ aplicado — dashboard + 6 alarmas conectadas al SNS (§16) |
| 9 | Destroy + apply desde cero | ⬜ **lo próximo** |
| 10 | Diagrama + presentación | 🟡 falta el diagrama |

`develop` está aplicado y `terraform plan` devuelve **No changes**. Ese es el punto de
partida: cualquier diff que aparezca en un plan a partir de ahora es tuyo.

---

## 3. Estructura real del repo

```
teracloud-lab3-terraform/
├── .gitattributes              ← * text=auto eol=lf. NO borrar, ver §8
├── .github/workflows/terraform-ci.yml
├── .tflint.hcl                 ← preset recommended + ruleset aws 0.48.0
├── CONVENCIONES.md
├── PLAN-FASES.md
├── README.md
├── backend/                    ← bucket de state, state local, ya corrido
├── docs/
│   ├── decisiones-modulos.md
│   ├── estado-actual.md        ← este archivo
│   └── runbook.md
├── environments/dev/
│   ├── backend.tf  locals.tf  main.tf  outputs.tf
│   ├── providers.tf  terraform.tfvars.example  variables.tf  versions.tf
└── modules/                    ← 14, uno por pieza de la arquitectura
    ├── acm/            alb/              cicd/         dns/
    ├── ecr/            ecs-cluster/      ecs-service/  efs/
    ├── github-oidc/    network/          notifications/
    ├── observability/  security-groups/  ssm-parameters/
```

**Los 14 módulos tienen contenido real.** El PR 0 había dejado 13 directorios con los 5
archivos en 0 bytes y se borraron: `tflint --recursive` los linteaba igual, no encontraba
el bloque `terraform` y marcaba `terraform_required_version` en cada uno — 9 warnings y
exit code 2, o sea el CI en rojo desde el primer PR.

**Cada módulo nació en su fase**, no antes: `network` y `security-groups` en la F1, `ecr`
en la F2, `ecs-cluster` en la F3, `efs`/`ssm-parameters`/`ecs-service` en la F4, `alb` en
la F5, `acm` y `dns` en la F6, `notifications`/`cicd`/`github-oidc` en la F7 y
`observability` en la F8.

Todo módulo lleva `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` y `README.md`,
y el `versions.tf` **tiene que traer `required_version`** o el CI se cae.

El `buildspec.yml` **no vive acá**: va en el repo de la app (`teracloud-lab3-app`), que
es lo que observa el pipeline.

---

## 4. Nomenclatura, con ejemplos reales

`local.name_prefix = "lab3-lc-${var.environment}"` → **`lab3-lc-dev`** (11 caracteres,
quedan 21 antes del tope de 32 del ALB y el Target Group).

| Recurso | Nombre real |
|---|---|
| VPC | `lab3-lc-dev-vpc` |
| Cluster ECS | `lab3-lc-dev-cluster` |
| ASG | `lab3-lc-dev-ecs-asg` |
| Capacity provider | `lab3-lc-dev-cp` |
| Repo ECR | `lab3-lc-dev-app` |
| SG de MySQL | `lab3-lc-dev-mysql-sg` |

En HCL: `snake_case`, y el recurso principal del módulo se llama **`this`**
(`aws_efs_file_system.this`, no `aws_efs_file_system.efs`).

**Tags**: solo `Name` a mano. El resto los pone `default_tags` del provider.
Excepción conocida: `aws_autoscaling_group` no hereda `default_tags` — ver §8.

---

## 5. Infraestructura viva

Estos son los valores reales, pero **no los hardcodees**: consumilos por output de
módulo desde `environments/dev/main.tf`.

| Recurso | Valor |
|---|---|
| VPC | `vpc-096e90b965a05ac86` (`10.0.0.0/16`) |
| Subnet privada AZ a | `subnet-047ac2855aa4b811e` — `us-east-1a` — `10.0.3.0/24` |
| Subnet privada AZ b | `subnet-0d8c55da2020ed17d` — `us-east-1b` — `10.0.4.0/24` |
| Subnets públicas | `subnet-02821eaa51ea4fa80`, `subnet-0baf52378bf3bb473` |
| SG ALB | `sg-02d23970cfa82fc0e` — ingress 443 desde internet |
| SG frontend | `sg-0b4800bd072a7c708` — ingress **80** desde SG-alb |
| SG mysql | `sg-02398ec338e7b8f51` — ingress 3306 desde SG-frontend |
| SG efs | `sg-0aeb1a39536193392` — ingress 2049 desde SG-mysql |
| SG instancias | `sg-0fc2428e8b1a96e9c` — sin inbound, a propósito |
| Cluster | `lab3-lc-dev-cluster`, ACTIVE, **3** instancias registradas |
| Namespace Cloud Map | `lab3.local` — `ns-zyl6fjw36lq6s4nb` |
| ECR | `104981180500.dkr.ecr.us-east-1.amazonaws.com/lab3-lc-dev-app` — tag `bootstrap` |
| ALB | `lab3-lc-dev-alb-258514894.us-east-1.elb.amazonaws.com` |
| Target groups | `lab3-lc-dev-fe-blue` y `lab3-lc-dev-fe-green`, `target_type = ip` |
| FQDN | `https://app.luccamedina.ownboarding.teratest.net` — certificado `ISSUED` |
| Servicios ECS | `lab3-lc-dev-mysql` (1 task) · `lab3-lc-dev-frontend` (2 tasks) |

Hay **1 solo NAT Gateway**, en la subnet pública de la AZ a. El tráfico saliente de la
subnet privada b cruza de AZ. Decisión de costo, ya documentada.



---

## 6. Interfaces disponibles

Los outputs de los módulos de base, que consume todo lo demás:

**`module.network`**
```
vpc_id · public_subnet_ids (list) · private_subnet_ids (list)
```

**`module.security_groups`**
```
alb_sg_id · frontend_sg_id · mysql_sg_id · efs_sg_id · cluster_sg_id
```

**`module.ecs_cluster`**
```
cluster_id · cluster_name · cluster_arn
capacity_provider_name          → va en capacity_provider_strategy de cada servicio
namespace_id · namespace_arn    → los consume aws_service_discovery_service
namespace_name                  → "lab3.local", para componer DB_HOST
asg_name · instance_role_name
```

**`module.ecr`**
```
repository_url · repository_arn · repository_name · registry_id
```

`environments/dev/main.tf` **no tiene ni un `resource`**: solo bloques `module`.

---

## 7. Correcciones a `PLAN-FASES.md` y `CONVENCIONES.md`

Los dos documentos se escribieron antes de leer el código de la app y antes de
verificar cosas contra el provider. **Estos puntos están desactualizados ahí:**

| Dónde | Dice | Va |
|---|---|---|
| PLAN F1 | frontend ← **3000** | **80** (la app es PHP/Apache) |
| PLAN F4 | `MYSQL_HOST` | **`DB_HOST`** — así se llama la variable que lee la app |
| PLAN F4 | 3 parámetros SSM | **6** — ver §9 |
| PLAN F5 | rolling + circuit breaker | **blue/green nativo de ECS** |
| PLAN F7 | tag = commit SHA | **fecha UTC + 7 del commit** |
| PLAN F8 | "alarma forzada a mano" | forzada vía `/api/chaos.php` y `/tmp/unhealthy` |
| CONV §2 | 11 módulos con esqueleto | 4 módulos reales; cada uno nace en su fase |
| CONV §2 | VPC de la comunidad | se hizo **propio** (ya está en `decisiones-modulos.md`) |
| CONV §2 | ACM módulo aparte | **fusionado dentro de `dns`**: cert + validación + alias son el mismo ciclo de vida |
| CONV §6 | rolling | blue/green |

**Módulo nuevo que no estaba en la lista**: `notifications`, con el SNS. Lo consumen la
Fase 7 y la Fase 8; si viviera dentro de `cicd`, la F8 dependería de la F7 sin razón.

### Blue/green: lo que cuesta

Verificado contra el schema del provider 6.61.0 — existe:

```hcl
deployment_configuration {
  strategy             = "BLUE_GREEN"
  bake_time_in_minutes = 5
  canary_configuration { canary_percent = 10, canary_bake_time_in_minutes = 5 }
}
```

Pero el precio lo paga el módulo `alb`, con 4 requisitos duros (los 3 primeros son
`required` en el schema):

1. **Dos target groups** — `target_group_arn` y `alternate_target_group_arn`.
2. **El tráfico de producción sale de un `aws_lb_listener_rule`**, no de la default
   action del listener: ECS necesita el ARN de una *rule* para swappearla.
3. **Un rol IAM** con `AmazonECSInfrastructureRolePolicyForLoadBalancers`, confiado a
   `ecs.amazonaws.com`.
4. Opcional: un **test listener** para probar la versión verde antes de darle tráfico.

Riesgo abierto a validar en la Fase 7: si el deploy provider ECS de CodePipeline con
`imagedefinitions.json` dispara bien el blue/green. Si no, el fallback es
`strategy = "ROLLING"` + `deployment_circuit_breaker`, que es un cambio de una línea.

---

## 8. Trampas ya pagadas

Cada una de estas costó tiempo. Están resueltas; el punto es **no reintroducirlas**.

**El ASG no hereda `default_tags`.** `aws_autoscaling_group` no expone `tags_all`. Se
resuelve con `data "aws_default_tags" "current" {}` dentro del módulo, expandido en
bloques `tag` con `propagate_at_launch = true`.

**`AmazonECSManaged` va declarado siempre.** ECS lo agrega al ASG por su cuenta al
asociarlo a un capacity provider, con o sin managed termination protection. Si no está
en el código, cada plan propone borrarlo: drift permanente y adiós al *No changes*.

**CRLF en el `user_data`.** Sin `.gitattributes`, git convierte a CRLF al checkout en
Windows y el heredoc del launch template se lleva los `\r` adentro del script. La
instancia arrancaría con `#!/bin/bash\r`, el intérprete no existe, `ECS_CLUSTER` nunca
se escribe en `/etc/ecs/ecs.config` y el cluster se queda en **0 instancias
registradas**. **No borrar `.gitattributes`.**

**Renombrar un recurso lo destruye.** Para Terraform un rename no es un rename. Si
cambiás el nombre de un recurso ya aplicado, va un bloque `moved`:

```hcl
moved {
  from = aws_ecr_repository.app
  to   = aws_ecr_repository.this
}
```

**`tflint` falla con módulos vacíos.** Un directorio con `.tf` en 0 bytes dispara
`terraform_required_version` y el job sale con exit 2. No crear esqueletos vacíos.

**ENIs por instancia.** Con `awsvpc` cada task consume una ENI. Verificado con
`describe-instance-types`: `t3.micro` tiene 2 ENIs (**1 slot** de task), `t3.small`,
`t3.medium` y `t3.large` tienen 3 (**2 slots**). En la familia t3, subir de tamaño no da
más ENIs — el colchón sale del número de instancias. Con 3 × `t3.small` hay **6 slots**;
en régimen corren 3 tasks y durante un swap blue/green son 5.

**`nonsensitive()` sobre `data.aws_ssm_parameter`.** El provider marca `value` como
sensible y el plan mostraría `(sensitive value)` en lugar del AMI ID.

**Docker Hub tiene límite de pulls por IP.** Las 3 instancias salen por un solo NAT, o
sea una sola IP. Para la imagen de MySQL, usar el espejo de AWS, que no tiene ese
límite (verificado, HTTP 200):

```
public.ecr.aws/docker/library/mysql:8.0
```

**Git Bash en Windows rompe las rutas que empiezan con `/`.** `aws ssm get-parameter
--name /aws/service/...` devuelve `ParameterNotFound` porque MSYS convierte la ruta.
Se arregla con `export MSYS_NO_PATHCONV=1`, o usando WSL.

**El `sub` del token OIDC trae los IDs numéricos adentro.** El trust policy de los roles
de GitHub Actions comparaba contra el formato que muestra toda la documentación:

```
repo:ctaddei/teracloud-lab3-terraform:pull_request
```

Pero este repositorio tiene activadas las claims endurecidas, que le agregan el ID del
owner y el del repositorio:

```
repo:ctaddei@14892265/teracloud-lab3-terraform@1341897797:pull_request
```

El `AssumeRoleWithWebIdentity` fallaba con `Not authorized to perform`, un error que
**no dice qué claim no coincidió**. Se diagnosticó imprimiendo el `sub` real desde un
step temporal del workflow; sin eso no hay forma de verlo. Los dos roles aceptan ahora
los dos formatos, con el comodín anclado después de la arroba — ver
`modules/github-oidc/README.md` para por qué `owner@*` y no `owner*`.

---

## 9. El contrato de la app

El repo `teracloud-lab3-app` trae un `SPEC-APP.md` que define qué espera de la
infraestructura. Lo esencial:

**Imagen**: `php:8.3-apache`, **puerto 80**. Build arg `APP_VERSION`, que la app
devuelve en `/api/status.php`.

**Variables de entorno** — se llaman `DB_*`, no `MYSQL_*`. `src/lib/db.php` chequea las
4 primeras y, si falta alguna, loguea `Missing required environment variable` y sirve en
modo degradado sin base. El síntoma es confuso: el health check sigue dando 200.

| SSM | Tipo | Lo consume |
|---|---|---|
| `/lab3/dev/db/host` | String | frontend `DB_HOST` ← **`mysql.lab3.local`** |
| `/lab3/dev/db/name` | String | frontend `DB_NAME` + mysql `MYSQL_DATABASE` |
| `/lab3/dev/db/user` | String | frontend `DB_USER` + mysql `MYSQL_USER` |
| `/lab3/dev/db/password` | SecureString | frontend `DB_PASSWORD` + mysql `MYSQL_PASSWORD` |
| `/lab3/dev/db/root_password` | SecureString | mysql `MYSQL_ROOT_PASSWORD` |
| `/lab3/dev/app/ops_token` | SecureString | frontend `OPS_TOKEN` |

Que los mismos tres valores alimenten las dos tasks es lo que impide que se
desincronicen. Y `DB_HOST` se compone desde `module.ecs_cluster.namespace_name`, así que
**no hay forma de escribir una IP sin hacerlo a propósito**.

Los secretos van por el bloque `secrets` de la task definition con `valueFrom`, nunca
por `environment`. **El rol que los resuelve es el de execution, no el de task**: el de
execution actúa antes de que el contenedor arranque. Confundirlos da un error que
parece de red.

**Health check del ALB**: `/health.php`, espera `200` y el texto `ok`. **Nunca toca la
base**, a propósito: si consultara MySQL, una caída de la base marcaría las 2 tasks del
frontend como unhealthy y ECS las mataría, convirtiendo una falla parcial en un outage
total. No "completar" ese endpoint.

**El schema se autoinicializa.** `db_init_schema()` corre en el primer request y aplica
`src/sql/schema.sql` si no existen las tablas. MySQL puede arrancar con el EFS vacío: no
hace falta `init.sql` ni entrypoint custom.

**Endpoints útiles para la Fase 8**: `/api/chaos.php` (header `X-Ops-Token`) setea
`error_rate`, `latency_ms` y `db_down` persistidos en MySQL, y el centinela
`/tmp/unhealthy` fuerza un 503 en el health check. Son las alarmas disparables a
demanda, sin romper nada.

---

## 10. Anatomía de la Fase 4 (aplicada)

Queda como referencia de cómo está armado `ecs-service`, que es el módulo que más
se toca de acá en adelante.

Tres módulos nuevos:

**`efs`** — file system, un mount target **por AZ** (las dos subnets privadas), access
point. Encriptado. El SG ya existe (`efs_sg_id`).
Outputs necesarios: `file_system_id`, `access_point_id`.

**`ssm-parameters`** — los 6 de la tabla del §9. `DB_HOST` se compone como
`"mysql.${var.namespace_name}"`.
Output necesario: un mapa de ARNs, porque el bloque `secrets` de la task definition
referencia el **ARN** del parámetro, no su valor.
*Decisión abierta*: de dónde salen las passwords. `random_password` deja el valor en el
state (que está cifrado en S3 y no se commitea) — es lo más simple y defendible para un
lab. La alternativa es crear el parámetro con `lifecycle { ignore_changes = [value] }` y
cargarlo a mano, lo que suma un paso al runbook.

**`ecs-service`** — el módulo que se invoca **dos veces**. Nace acá, pero tiene que
nacer **genérico**, porque la Fase 5 lo reusa para el frontend sin tocarlo.

```
aws_cloudwatch_log_group.this
aws_iam_role.task_execution + attachment + policy inline (ssm:GetParameters, kms:Decrypt)
aws_iam_role.task                    (vacío por ahora: la app no llama a AWS)
aws_ecs_task_definition.this         (container_definitions = jsonencode([...]))
aws_service_discovery_service.this   (condicional)
aws_ecs_service.this
```

Lo que cambia entre las dos invocaciones se resuelve con bloques `dynamic` sobre
variables que son `null` por defecto:

| | mysql (F4) | frontend (F5) |
|---|---|---|
| `load_balancer` | no | sí |
| `service_registries` (Cloud Map) | sí | no |
| volumen EFS | sí | no |
| `ordered_placement_strategy` | ninguna | spread × 2 |
| imagen | `public.ecr.aws/docker/library/mysql:8.0` | la del ECR |
| tasks | 1 | 2 |

⚠️ **`lifecycle.ignore_changes` no acepta condicionales.** No se puede hacer
`ignore_changes = var.x ? [...] : []`. O se ignora `task_definition` en las dos
invocaciones (mysql tampoco sufre por eso), o se parte el recurso en dos. Es la única
trampa real del módulo genérico — conviene decidirlo antes de escribirlo, no después.

**Listo cuando**: la task de MySQL está `RUNNING`, y al matarla a mano el servicio la
repone y los datos siguen ahí.

```bash
aws ecs describe-tasks --cluster lab3-lc-dev-cluster --tasks <arn> \
  --query 'tasks[0].[lastStatus,stoppedReason]'

aws servicediscovery discover-instances \
  --namespace-name lab3.local --service-name mysql
```

`describe-tasks` es la **primera** parada de troubleshooting, no la última.

---

## 11. Flujo de trabajo

Una rama por fase, un PR a `develop`, **1 approval del otro**. Squash al mergear.
Conventional Commits.

El apply sale de **`develop`**, después del merge. Nunca desde una rama de feature: si
tu rama salió de `develop` antes de que se mergeara otra fase, un apply desde ahí
propone **destruir** lo que la otra fase creó.

**No se aplica de a dos**: el lock de S3 hace fallar limpio al segundo, pero se avisa
igual antes de cada apply.

Antes de pushear, correr lo mismo que el CI:

```bash
terraform fmt -check -recursive
terraform -chdir=environments/dev init -backend=false && terraform -chdir=environments/dev validate
tflint --init && tflint --recursive     # tiene que dar exit 0
```

Y después de cada apply, la verificación que vale por todas:

```bash
terraform plan     # → "No changes. Your infrastructure matches the configuration."
```

Ese *No changes* es un ítem del DoD. Si un plan post-apply propone algo, hay drift y hay
que arreglarlo en el momento, no en la Fase 9.

---

## 12. Deudas abiertas

- `docs/arquitectura.drawio` no existe todavía (Fase 10).
- Falta activar en `develop` el *Require status checks to pass before merging*. Ahora
  tiene sentido hacerlo: con el job `plan` andando hay un check que vale la pena exigir.
- Falta la corrida de caos que le dé historial a las alarmas y datos al panel de negocio
  (§16). Va **después** de la Fase 9: el destroy se lleva las métricas igual.
- Quedan ramas mergeadas sin borrar en el remoto. No molestan, pero ensucian el
  historial que los mentores van a mirar.

### El job `plan` del CI, resuelto

Estuvo dormido desde la Fase 0 y se activó recién ahora. Hacían falta tres cosas, y las
tres estaban a medias:

| Qué faltaba | Estado |
|---|---|
| El rol OIDC de solo lectura | Existía desde la Fase 7, pero sin usar |
| Que su trust policy aceptara el `sub` real | Arreglado — ver §8 |
| La variable de repo `AWS_PLAN_ROLE_ARN` | Seteada a mano con el output `plan_role_arn` |

El job corre **solo en `pull_request`**. El rol de plan confía únicamente en el `sub` de
ese evento, así que en el `push` a `develop` posterior al merge el
`AssumeRoleWithWebIdentity` fallaría — y ahí tampoco queremos un plan: el `apply` lo
corremos a mano.

Con esto cada PR muestra el diff real contra la infraestructura viva, que es la
diferencia entre "el código compila" y "este PR destruye la VPC". Es lo que
`CONVENCIONES.md` §4 venía prometiendo.

## 13. Verificación del despliegue

Salida real del entorno, no la esperada.

```
frontend  2/2  rolloutState COMPLETED
mysql     1/1  rolloutState COMPLETED

curl -I http://<alb>   → 301   Location: https://app.luccamedina...:443/
curl -I https://<fqdn> → 200   Apache/2.4.68 · PHP/8.3.33

/api/status.php
  version: bootstrap
  db: { ok: true, host: "mysql.lab3.local", resolved_ip: "10.0.4.130" }
  distribución: 9f29013b → us-east-1a · 43d450f9 → us-east-1b

terraform plan → No changes. Your infrastructure matches the configuration.
```

`db.host` es un nombre y no una IP: eso cierra la lección del Lab 2 con evidencia.

**Los targets están en `green`, no en `blue`.** ECS trató el primer despliegue como un
blue/green: colocó las tasks en el target group alterno y reescribió la listener rule.
Que `lab3-lc-dev-fe-blue` tenga 0 targets es lo esperado. Y es la razón por la que la
rule lleva `ignore_changes = [action]`: sin eso, cada `plan` propondría devolverla a
blue, y ese cambio movería el tráfico de producción por fuera del deployment.

### Prueba de persistencia de MySQL

El *listo cuando* de la Fase 4. Se hizo **por HTTP, sin entrar al contenedor**: se crea
una orden real desde la app, se mata la task de MySQL y se vuelve a consultar.

```
task vieja  767312a8...  ->  stop-task
task nueva  24c70fa7...  ->  RUNNING

ANTES:   orders_total 2 · revenue 20793 · mysql.lab3.local -> 10.0.4.130
DESPUES: orders_total 2 · revenue 20793 · mysql.lab3.local -> 10.0.3.51
```

La orden `id: 2` sigue en `/api/orders.php` con su timestamp, su total y el `task_id`
del frontend que la procesó.

Lo que hace fuerte a la prueba son las dos cosas que cambiaron y la que no:

- Cambió la task.
- **Cambió la IP**: `10.0.4.130` -> `10.0.3.51`. La task nueva ni siquiera cayó en la
  misma AZ.
- **No cambió el nombre**: `mysql.lab3.local` siguió resolviendo y el frontend no se
  enteró de nada.

Ese cambio de IP es exactamente el incidente del Lab 2. Con la IP hardcodeada, ahí
empezaban las dos horas de outage. Acá el frontend siguió sirviendo sin tocar una línea
de configuración, porque `DB_HOST` sale de Cloud Map. Y los datos sobrevivieron porque
están en EFS, no en el disco efímero de la task.

### Ítems del DoD ya verificados

- [x] `curl -I http://<fqdn>` → 301 · `curl -I https://<fqdn>` → 200
- [x] `terraform plan` post-deploy → **No changes**
- [x] `terraform fmt -check -recursive` y `tflint` verdes
- [x] Backend S3 con lock nativo, sin DynamoDB
- [x] Módulos propios para red, ECS, ALB, EFS, MySQL
- [x] Parámetros en SSM, inyectados en la task definition
- [x] Push a `main` de la app → pipeline verde + mail del SNS (§15)
- [x] Dashboard + alarmas + notificaciones por mail (§16)

### Falta

- [ ] Fase 9 — destroy + apply desde cero siguiendo el runbook
- [ ] Una alarma forzada que dispare el mail — la corrida de caos (§16)
- [ ] Diagrama de arquitectura y doc de decisiones (Fase 10)

---

## 14. Plan de la Fase 7, *antes* de ejecutarla — histórico

> ⚠️ **Esto es el plan, no el estado.** Se escribió antes de aplicar la Fase 7 y se
> conserva porque varios README lo referencian y porque las decisiones de diseño que
> justifica —el formato del tag, la separación de `notifications`, los dos roles OIDC—
> siguen siendo las vigentes.
>
> **Para saber qué pasó de verdad, ir a §15.** Donde los dos se contradigan, manda §15.
> El riesgo 1 de más abajo (si el deploy provider ECS dispara el blue/green) quedó
> **resuelto que sí**: el fallback a rolling nunca hizo falta.

**La hizo Christian.** Se toca con la Fase 8 solo en el SNS: el módulo `notifications`
lo escribe quien llegue primero y el otro lo consume.

### Qué tiene que pasar

```
push a main de lab3-app-lc
   |__ CodeStar Connection -> CodePipeline
        |- Source : el repo de la app
        |- Build  : CodeBuild -> docker build -> push a ECR con tag fecha+commit
        |_ Deploy : provider ECS con imagedefinitions.json
                      |__ ECS aplica el blue/green y el sitio sirve el cambio
   |__ SNS -> mail
```

### Módulos

| Módulo | Contenido |
|---|---|
| `notifications` **(nuevo)** | Topic SNS + suscripción por mail. Aparte de `cicd` porque lo consumen la F7 y la F8; adentro, la observabilidad dependería del pipeline sin razón |
| `cicd` | Bucket de artifacts, CodeStar Connection, CodeBuild + su rol, CodePipeline, reglas de EventBridge que notifican al SNS |
| `github-oidc` **(nuevo)** | Proveedor OIDC + dos roles: lectura para `plan`, escritura para `apply` |

Y en el repo de la app: **`buildspec.yml`**, que hoy no existe.

### Los tres riesgos, en orden

**1. El deploy provider ECS con blue/green.** Es la incógnita abierta desde que elegimos
blue/green. El provider hace `UpdateService` con la task definition nueva y, con la
estrategia a nivel servicio, ECS *debería* aplicar el blue/green solo. No está
verificado. **Fallback**: `blue_green = null` en la invocación del frontend — una línea,
y queda rolling con circuit breaker.

**2. El `imagedefinitions.json` necesita el nombre exacto del contenedor**, que es
`frontend` (lo expone el módulo como output, pero el buildspec lo escribe igual):

```json
[{"name":"frontend","imageUri":"<repo>:<tag>"}]
```

**3. La Connection nace en `PENDING`** y se autoriza a mano en la consola. Es la segunda
de las dos excepciones al "sin consola", ya anotada en el runbook.

### El tag de la imagen

```bash
TAG="$(date -u +%Y%m%d-%H%M%S)-${CODEBUILD_RESOLVED_SOURCE_VERSION:0:7}"
docker build --build-arg APP_VERSION=$TAG -t $REPO:$TAG .
```

UTC porque la imagen `bootstrap` se pushea a mano desde una máquina en hora local y el
pipeline corre en un contenedor en UTC: sin `-u`, los tags de las dos fuentes no ordenan
entre sí. El sufijo del commit da trazabilidad, que un tag por fecha sola no tiene.

**`APP_VERSION` es lo que hace verificable el deploy**: hoy `/api/status.php` devuelve
`bootstrap`, y después del primer pipeline tiene que devolver el tag nuevo. Sin eso,
"el pipeline dio verde" no prueba que el sitio cambió.

### OIDC

`CONVENCIONES` §6 lo da por decidido y se hace: dos roles con trust policy distinta
sobre el mismo proveedor.

| Rol | Trust | Permisos |
|---|---|---|
| `...-gha-plan` | `sub` = `repo:<owner>/<repo>:pull_request` | Solo lectura |
| `...-gha-apply` | `sub` = `repo:<owner>/<repo>:ref:refs/heads/develop` | Escritura |

Un PR no puede aplicar: esa es toda la razón de separarlos. El ARN del rol de lectura va
en la variable de repo `AWS_PLAN_ROLE_ARN`, que el workflow ya consulta — hoy el job de
`plan` está gateado por esa variable y por eso nunca corrió.

> Corrección a `CONVENCIONES` §6: dice *"trust policy con el `sub` exacto de
> CloudTrail"*. CloudTrail no interviene — el `sub` sale de los claims del token que
> emite GitHub Actions.

### Orden de trabajo

1. `notifications` y confirmar la suscripción por mail (llega un mail que hay que
   aceptar; sin eso el topic no notifica).
2. `buildspec.yml` en el repo de la app.
3. `cicd`: bucket, Connection, CodeBuild, CodePipeline.
4. Autorizar la Connection en la consola.
5. `github-oidc` y setear `AWS_PLAN_ROLE_ARN` en el repo.
6. Push trivial a `main` de la app y mirar el pipeline entero.
7. **`terraform plan` -> No changes.** Si aparece drift después del primer deploy, falta
   un `ignore_changes`.

### Listo cuando

- El pipeline queda verde end-to-end.
- Llega el mail del SNS.
- `/api/status.php` devuelve el **tag nuevo** en `version`, no `bootstrap`.
- `terraform plan` sigue dando `No changes`.

---

## 15. Fase 7 — CI/CD (aplicada)

Este apartado registra el estado real de la Fase 7, para no depender de
recordar una conversación puntual. Es el **estado**; §14 es el plan previo.
Donde se contradigan, manda esto.

### Ya resuelto

- **Los tres módulos nuevos están escritos y aplicados**: `notifications`, `cicd`,
  `github-oidc`.
- **`notifications`**: topic SNS + `for_each` sobre una lista de emails
  (hoy solo `taddeichristian@gmail.com`; agregar un segundo mail es sumar un
  string a `var.notification_emails` y aplicar, no hace falta tocar el
  módulo). Incluye la resource policy que necesita
  `codestar-notifications.amazonaws.com` para poder publicar — sin eso, la
  notification rule de `cicd` queda creada pero no entrega nada, en
  silencio.
- **`cicd`**: bucket de artifacts, CodeStar Connection, CodeBuild
  (`privileged_mode = true`, necesario para `docker build`), CodePipeline con
  deploy provider **ECS** (no CodeDeployToECS) usando
  `imagedefinitions.json`, y `aws_codestarnotifications_notification_rule`
  apuntando al SNS de `notifications`.
- **`github-oidc`**: OIDC provider (thumbprint resuelto en vivo contra
  `token.actions.githubusercontent.com`, no hardcodeado) + dos roles —
  `plan` con `ReadOnlyAccess`, asumible desde cualquier PR del repo de IaC;
  `apply` con `AdministratorAccess`, asumible **solo** desde `ref:refs/heads/develop`.
  Decisión documentada en el README del módulo: el control real de "quién
  puede aplicar" lo da la condición de rama en el trust policy, no el
  alcance de la política adjunta.
- **`buildspec.yml`** escrito para el repo de la app (`teracloud-lab3-app`,
  no el de IaC). Tag = fecha UTC + 7 caracteres del commit, como corrige §7 a
  `PLAN-FASES.md`. Escribe `imagedefinitions.json` con el nombre de
  contenedor `"frontend"` — tiene que matchear exacto el `name` del
  `container_definitions` en la invocación de `ecs-service` para el
  frontend.

### Resultado

Pipeline verde end-to-end, disparado por un push real a `main` del repo de la app:

```
Source ✅   Build ✅   Deploy ✅

version del sitio:  20260825-013728-8e950a7   (antes decia "bootstrap")
ECR:                bootstrap · 20260825-013728-8e950a7 + latest
```

Ese cambio de string en `/api/status.php` es la prueba de que el deploy reemplazo la
imagen. El pipeline en verde por si solo no lo demuestra.

**El blue/green nativo funciono con el deploy provider ECS de CodePipeline.** Era la
incognita abierta desde que lo elegimos (§14, riesgo 1) y el fallback a rolling no hizo
falta.

### Los cuatro errores que costo hacerlo andar

Ninguno se veia en `fmt`, `validate`, `tflint` ni `plan`. Todos aparecieron ejecutando,
y ninguno fue un error de diseno: la arquitectura no cambio.

| Error | Causa | Donde |
|---|---|---|
| `ConfigurationException` al crear la notification rule | El service-linked role de CodeStar Notifications no existia. El propio intento fallido lo crea | Reintentar el apply |
| Build muerto en fase `QUEUED` | El ARN de la policy decia `/codebuild/<proyecto>`; el log group real es `/aws/codebuild/<proyecto>` | `modules/cicd` |
| `Bad substitution` | `${VAR:0:7}` es sintaxis de bash y CodeBuild ejecuta con `/bin/sh` (dash) | `buildspec.yml` de la app |
| `The provided role does not have sufficient permissions to access ECS` | Faltaban `ecs:DescribeTasks`, `ecs:ListTasks` y `ecs:TagResource` | `modules/cicd` |

**Ojo para la Fase 9**: el primero **no se va a repetir**, porque el service-linked role
ya existe en la cuenta. Pero en una cuenta nueva vuelve a pasar, asi que esta anotado en
el runbook aunque nosotros no lo veamos otra vez.

## 16. Fase 8 — Observabilidad (aplicada)

Un dashboard y seis alarmas, sin agregar ningun agente: las tres fuentes de metricas ya
existian.

| Fuente | Aporta |
|---|---|
| `AWS/ApplicationELB` | Latencia, trafico, errores, targets sanos |
| `ECS/ContainerInsights` | CPU, memoria y tasks por servicio |
| `Lab3/Ecommerce` (EMF) | **Pedidos y facturacion**, que la app ya escribia a stdout |

Esa tercera fila es lo que separa este dashboard de uno generico: un pico de 5xx no dice
cuanto costo, `PedidosFallidos` si.

### Las seis alarmas

Nacieron en **`OK`**, no en `INSUFFICIENT_DATA`, porque `treat_missing_data` esta elegido
alarma por alarma en vez de dejarse en el default:

| Alarma | Sin datos significa | Eleccion |
|---|---|---|
| 5xx, latencia, memoria, pedidos fallidos | Nadie uso el sitio | `notBreaching` |
| `RunningTaskCount` | El servicio dejo de reportar | `breaching` |
| `UnHealthyHostCount` | No hay targets registrados | `breaching` |

Las de targets **suman los dos target groups**: el blue/green alterna cual esta activo, y
mirar uno solo deja la alarma ciega despues de cada deploy.

Los umbrales estan elegidos a ojo, y cada alarma lo dice en su `alarm_description` — la
salvedad viaja a la consola, no se queda en un README.

### Falta

- [ ] Una corrida de caos con `/api/chaos.php` para que las alarmas tengan historial y
  el panel de negocio no este vacio en la demo. Es ademas el item del DoD
  ("una alarma forzada dispara el mail"). Conviene hacerlo **despues** de la Fase 9,
  con la infra recien levantada.

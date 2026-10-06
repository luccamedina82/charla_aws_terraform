# Plan por fases — Desafío IaC (Lab 3)

> **Documento histórico.** Describe el Lab 3 original de Teracloud (app PHP de e-commerce, dominio `teratest.net`, módulos `github-oidc` y `observability`). No refleja la versión adaptada para la charla. Para el estado actual ver `README.md` y `docs/runbook.md`.

**Regla única**: no se arranca una fase sin el *Listo cuando* de la anterior en verde.
Cada fase = una rama `feature/*` = un PR a `develop`.

| # | Fase | Día | Quién |
|---|---|---|---|
| 0 | Acuerdos y backend de estado | Vie 21 | Los dos |
| 1 | Red y seguridad | Vie 21 – Sáb 22 | Los dos (pair) |
| 2 | ECR + imagen bootstrap | Sáb 22 | Christian |
| 3 | Cluster ECS | Sáb 22 – Dom 23 | Lucca |
| 4 | EFS + MySQL + SSM | Dom 23 – Lun 24 | Lucca |
| 5 | ALB + frontend | Lun 24 | Christian |
| 6 | DNS + HTTPS | Lun 24 | Christian |
| 7 | CI/CD | Mar 25 | Christian |
| 8 | Observabilidad | Mar 25 | Lucca |
| 9 | Prueba de reproducibilidad | Mié 26 (mañana) | Los dos |
| 10 | Documentación y presentación | Mié 26 (tarde) | Cada uno la suya |

El reparto es ajustable, pero **cada uno revisa el PR del otro** — en la presentación
individual los dos tienen que poder defender el 100%.

---

## Fase 0 — Acuerdos y backend de estado
**Hace**: crear los dos repos · mergear `CONVENCIONES.md` · crear el bucket de estado
desde `backend/` · **PR 0**: `variables.tf` + `outputs.tf` de los 11 módulos, vacíos
de lógica · `.gitignore`, `versions.tf`, `providers.tf` con `default_tags`.

**Listo cuando**: `terraform init` en `environments/dev` conecta al backend S3 y
`terraform plan` devuelve *0 to add* sin errores.

**Ojo**: el PR 0 es lo que permite trabajar en paralelo. Si arrancan a escribir
`resource` sin haber firmado las interfaces, integrar el lunes es un infierno.

---

## Fase 1 — Red y seguridad
**Rama** `feature/network` · **Depende de** F0
**Hace**: VPC `10.0.0.0/16` · 2 subnets públicas + 2 privadas en `us-east-1a/1b` ·
IGW · 1 NAT Gateway (decisión de costo) · route tables · los 4 SGs como recursos
separados (ALB ← 443 internet · frontend ← 3000 desde SG-alb · mysql ← 3306 desde
SG-frontend · EFS ← 2049 desde SG-mysql).

**Listo cuando**: `terraform apply` limpio y las subnets privadas rutean a NAT.

**Ojo**: hacer esta fase **en pair**, aunque sea una hora. Todo lo demás depende de
sus outputs; un error acá se paga diez veces.

---

## Fase 2 — ECR + imagen bootstrap
**Rama** `feature/ecr` · **Depende de** F0
**Hace**: repo ECR con `scan_on_push` y `force_delete = true` · `Dockerfile` de la app
PHP en `lab3-app-lc` · build y push manual de una imagen con tag `bootstrap`.

**Listo cuando**: `aws ecr list-images` muestra el tag `bootstrap`.

**Ojo**: esto rompe la dependencia circular imagen ↔ servicio ECS. Sin imagen previa,
la Fase 4 y 5 no llegan nunca a steady state. Documentar el paso en `runbook.md`.

---

## Fase 3 — Cluster ECS
**Rama** `feature/ecs-cluster` · **Depende de** F1
**Hace**: cluster (EC2 mode) · launch template con AMI ECS-optimized vía data source ·
ASG en 2 AZs · capacity provider con managed scaling · IAM role de instancia
(`AmazonEC2ContainerServiceforEC2Role` + `AmazonSSMManagedInstanceCore`).

**Listo cuando**: `aws ecs describe-clusters` muestra
`registeredContainerInstancesCount` igual al desired del ASG.

**Ojo**: **techo de ENIs**. Con `awsvpc`, cada task consume una ENI y el tipo de
instancia las limita. Dimensionar `t3.small` mínimo, y `min` del ASG con colchón para
que el deployment pueda colocar tasks nuevas antes de matar las viejas.
No olvidar `AmazonSSMManagedInstanceCore`: sin eso no hay Session Manager para debuggear.

---

## Fase 4 — EFS + servicio MySQL + Parameter Store
**Rama** `feature/mysql-efs` · **Depende de** F3
**Hace**: EFS + mount target por AZ + access point · namespace Cloud Map · parámetros
SSM (`/lab3/db/host`, `/lab3/db/user`, `/lab3/db/password` como SecureString) ·
`ecs-service` invocado para mysql: 1 task, volumen EFS, service discovery.


**Listo cuando**: la task está `RUNNING`, y al matarla a mano el servicio la repone y
los datos siguen ahí (`SELECT` desde la nueva task devuelve lo insertado en la vieja).

**Ojo**: `MYSQL_HOST` **nunca** una IP — `mysql.<namespace>` vía Cloud Map. Es el error
del Workshop 4 que costó 2 horas. Y la password va por bloque `secrets`, no `environment`.

---

## Fase 5 — ALB + servicio frontend
**Rama** `feature/alb-frontend` · **Depende de** F2, F4
**Hace**: ALB internet-facing · target group `target_type = ip` · listener 80 con
redirect 301 a 443 · `ecs-service` invocado para frontend: 2 tasks, placement strategy
`spread` por AZ + por instancia, `ignore_changes` en `task_definition`.

**Listo cuando**: `curl -I http://<dns-del-alb>` → **301** y el target group muestra
2 targets `healthy` en AZs distintas.

**Ojo**: el nombre del TG y del ALB, máximo 32 caracteres. El listener 443 todavía no
existe (falta el cert) — dejarlo para la F6, no bloquear acá.

---

## Fase 6 — DNS + HTTPS
**Rama** `feature/dns-acm` · **Depende de** F5
**Hace**: certificado ACM con validación DNS · registro alias en Route 53 apuntando al
ALB · listener 443 con el cert.

**Listo cuando**: `curl -I https://<fqdn>` → **200** y `curl -I http://<fqdn>` → **301**.

**Ojo**: el `apply` se queda esperando la validación del cert. Es normal, tarda unos
minutos; no cortarlo (un `plan` interrumpido deja el lock huérfano en S3).

---

## Fase 7 — CI/CD
**Rama** `feature/cicd` · **Depende de** F5
**Hace**: CodeStar Connection · bucket de artifacts · CodeBuild (build + push a ECR con
tag = commit SHA, registry por variable de entorno) · CodePipeline con source en
`lab3-app-lc` rama `main` y deploy provider **ECS** con `imagedefinitions.json` ·
SNS + suscripción por mail · circuit breaker con rollback.

**Listo cuando**: un push trivial a `main` de la app deja el pipeline verde end-to-end,
llega el mail del SNS, y el sitio sirve el cambio.

**Ojo**: la Connection nace en `PENDING` — autorizarla a mano en la consola y anotarlo
como la excepción al "sin consola". Después del primer deploy, `terraform plan` tiene
que seguir dando "No changes" (si no, falta el `ignore_changes`).

---

## Fase 8 — Observabilidad
**Rama** `feature/observability` · **Depende de** F5
**Hace**: alarmas sobre `HTTPCode_ELB_5XX_Count`, `TargetResponseTime` p99,
`UnHealthyHostCount`, `CPUUtilization` / `MemoryUtilization` del servicio,
`RunningTaskCount` · dashboard con todo junto · las alarmas notifican al SNS de la F7.

**Listo cuando**: el dashboard renderiza con datos reales y una alarma forzada a mano
dispara el mail.

**Ojo**: las alarmas se crean aunque la métrica no exista todavía — nacen en
`INSUFFICIENT_DATA` y pasan a `OK` con el primer datapoint. Justificar cada umbral:
"elegido a ojo por falta de historial, en producción saldría de un SLO".

---

## Fase 9 — Prueba de reproducibilidad
**Depende de** todo. **Esta fase no es opcional**: el DoD pide código "reproducible y
que se pueda ejecutar sin errores", y eso solo se sabe probándolo.

**Hace**: `terraform destroy` completo · `terraform apply` desde cero siguiendo el
`runbook.md` al pie de la letra, sin improvisar · cronometrarlo.

**Listo cuando**: la infra vuelve a estar arriba, el sitio responde por HTTPS, y el
único paso manual fue el del runbook (push de la imagen bootstrap + autorizar la
Connection). Después: `develop` → `main`, tag `v1.0-entrega`.

**Ojo**: reservar la mañana entera. Acá aparecen los problemas de orden de creación
que el apply incremental esconde.

---

## Fase 10 — Documentación y presentación
**Hace**: diagrama de arquitectura (draw.io) · `docs/decisiones-modulos.md` (por qué
comunidad y por qué propios, módulo por módulo) · `runbook.md` final ·
README de cada módulo · tabla lab-vs-producción · presentación individual.

**Listo cuando**: alguien ajeno al equipo puede clonar el repo, leer el runbook y
levantar la infra sin preguntar nada.

---

## Checklist de entrega (DoD verificable)

- [ ] `curl -I http://<fqdn>` → 301 · `curl -I https://<fqdn>` → 200
- [ ] URL pública del ALB + FQDN entregados
- [ ] Push a `main` de la app → pipeline verde + mail del SNS
- [ ] `terraform plan` post-deploy → **No changes**
- [ ] `terraform fmt -check -recursive` y `tflint` verdes en CI
- [ ] Destroy + apply desde cero, exitoso (Fase 9)
- [ ] Backend S3 con lock nativo, sin DynamoDB
- [ ] Módulos propios para red, ECS, ALB, EFS, MySQL
- [ ] Dashboard + alarmas + notificaciones por mail
- [ ] Parámetros en SSM, inyectados en la task definition
- [ ] Repos compartidos con los mentores, Git Flow visible en el historial
- [ ] Diagrama + doc de decisiones de módulos

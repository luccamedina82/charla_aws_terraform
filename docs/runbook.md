# Runbook — levantar el entorno desde cero

Cómo pasar de una cuenta AWS vacía al sitio sirviendo por HTTPS.

**Regla de este documento**: se sigue al pie de la letra, sin improvisar. Si algo no
sale como está escrito acá, el runbook está mal y hay que corregirlo — no resolverlo a
mano y seguir. Es la prueba de la Fase 9.

---

## Antes de empezar

| Requisito | Verificación |
|---|---|
| AWS CLI con credenciales | `aws sts get-caller-identity` |
| Terraform ≥ 1.11 | `terraform version` |
| Docker | `docker --version` |
| Plugin de Session Manager | `session-manager-plugin --version` |
| Hosted zone en Route 53 | `aws route53 list-hosted-zones` |

El plugin de Session Manager no viene con el AWS CLI y `aws ecs execute-command` lo
necesita. En Ubuntu / WSL:

```bash
curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o /tmp/smp.deb
sudo dpkg -i /tmp/smp.deb
```

---

## Paso 1 — Bucket de estado

Solo la primera vez en una cuenta nueva. Tiene state local y se corre una sola vez.

```bash
cd backend
terraform init
terraform apply
```

Anotar el nombre del bucket que sale por output y ponerlo en
`environments/dev/backend.tf`. El bloque `backend` se evalúa antes que las variables,
así que solo acepta literales: el nombre va escrito ahí y en ningún otro lugar.

---

## Paso 2 — Red, cluster y ECR

```bash
cd environments/dev
terraform init
terraform apply -target=module.network -target=module.security_groups \
                -target=module.ecr -target=module.ecs_cluster
```

Se aplica con `-target` a propósito: el resto depende de que exista la imagen
`bootstrap`, que todavía no está.

**Verificación** — tiene que dar `3`:

```bash
aws ecs describe-clusters --clusters lab3-lc-dev-cluster \
  --query 'clusters[0].registeredContainerInstancesCount'
```

Si da `0`, el orden de sospecha es: el `user_data` no escribió `ECS_CLUSTER` en
`/etc/ecs/ecs.config` → falta la policy `AmazonEC2ContainerServiceforEC2Role` en el rol
de instancia → las instancias no tienen salida por el NAT.

---

## Paso 3 — Imagen bootstrap (paso manual)

**Es una de las dos excepciones al "todo por código"** y no se puede evitar: el servicio
ECS no alcanza *steady state* si la imagen que referencia su task definition no existe.
Como la task definition la crea Terraform y la imagen la construye el pipeline, hay una
dependencia circular. Se rompe pusheando la imagen a mano una vez.

```bash
git clone https://github.com/luccamedina82/charla_aws_app.git
cd charla_aws_app

REPO=$(terraform -chdir=../charla_aws_terraform/environments/dev output -raw ecr_repository_url)

aws ecr get-login-password --region us-east-1 --profile lab3 \
  | docker login --username AWS --password-stdin "${REPO%%/*}"

# El Dockerfile está en app/, no en la raíz del repo.
docker build --platform linux/amd64 --build-arg APP_VERSION=bootstrap -t "$REPO:bootstrap" ./app
docker push "$REPO:bootstrap"
```

`--platform linux/amd64` porque las instancias son `t3.small` (x86_64). Una imagen ARM
falla con `exec format error`, que no dice nada sobre arquitecturas.

`--build-arg APP_VERSION=bootstrap` hace que el pie de página muestre `bootstrap` como
versión: es cómo se confirma después que el pipeline realmente reemplazó algo. Depende
del cambio 6 de la app (versión visible); hasta entonces el build-arg se ignora.

**Verificación**:

```bash
aws ecr list-images --repository-name lab3-lc-dev-app --query 'imageIds[].imageTag'
```

---

## Paso 4 — Todo lo demás

```bash
cd environments/dev
terraform apply
```

**El apply se queda varios minutos en `module.acm.aws_acm_certificate_validation`.** Es
normal: espera a que ACM valide el dominio por DNS. **No cortarlo** — un apply
interrumpido deja el archivo de lock huérfano en S3 y el siguiente falla.

---

## Paso 4b — Los tres pasos manuales del CI/CD

El apply del paso 4 crea el pipeline, pero **no queda funcionando solo**.

**1. El primer apply va a fallar creando la notification rule.**

```
ConfigurationException: AWS CodeStar Notifications could not create the
AWS CloudWatch Events managed rule in your AWS account...
```

CodeStar Notifications necesita un service-linked role que AWS crea recién cuando
alguien intenta usar el servicio: **ese intento fallido es el que lo crea**. Se resuelve
volviendo a correr `terraform apply`. No hay nada que arreglar en el código.

> Si el rol ya existe en la cuenta (`aws iam list-roles --path-prefix
> /aws-service-role/codestar-notifications.amazonaws.com/`), este error no aparece.

**2. Autorizar la CodeStar Connection.** Nace en `PENDING` y el handshake OAuth con
GitHub no tiene API — es *la* excepción al "sin consola".

Consola → **Developer Tools** → **Settings** → **Connections** → la connection
`lab3-lc-dev-github` → **Update pending connection** → autorizar la app *AWS Connector
for GitHub* → dar acceso al repo **de la app** (`charla_aws_app`), no al de IaC.

```bash
aws codestar-connections list-connections   --query 'Connections[].[ConnectionName,ConnectionStatus]' --output text
# tiene que decir AVAILABLE
```

**3. Confirmar las suscripciones de mail.** Cada dirección de
`var.notification_emails` recibe un pedido de confirmación. **Hasta que no se haga clic,
el topic no notifica a nadie** — y no hay ningún error visible: las alarmas disparan y
el mail no llega.

```bash
aws sns list-subscriptions   --query 'Subscriptions[?contains(TopicArn,`lab3-lc-dev`)].[Endpoint,SubscriptionArn]'   --output text
# una suscripcion sin confirmar dice "PendingConfirmation" en vez de un ARN
```

Con eso hecho, el pipeline probablemente tenga una ejecución fallida del arranque
automático, de cuando la Connection todavía estaba `PENDING`. Se relanza:

```bash
aws codepipeline start-pipeline-execution --name lab3-lc-dev-pipeline
```

---

## Paso 5 — Verificación

```bash
# El sitio
curl -I http://$(terraform output -raw alb_dns_name)   # 301
curl -I $(terraform output -raw site_url)              # 200

# Los servicios
aws ecs describe-services --cluster lab3-lc-dev-cluster \
  --services lab3-lc-dev-frontend lab3-lc-dev-mysql \
  --query 'services[].[serviceName,runningCount,desiredCount,deployments[0].rolloutState]' \
  --output text

# El health check del ALB (no toca la base)
curl -s $(terraform output -raw site_url)/api/health

# Que task respondio y en que AZ. Repetirlo: tiene que alternar entre dos
curl -s $(terraform output -raw site_url)/api/whoami

# Sin drift: esto es un item del DoD
terraform plan
```

Lo que tiene que dar:

- `/api/health` responde 200.
- `/api/whoami` alterna entre dos tasks, una por AZ.
- El pie de página **no** dice `bootstrap` después del primer pipeline.
- `terraform plan` → **No changes**.

**Dónde están los targets**: ECS trata el primer despliegue como un blue/green, así que
las tasks quedan registradas en el target group **green** y la listener rule apunta ahí.
Que `lab3-lc-dev-fe-blue` tenga 0 targets es lo esperado, no un error.

---

## Operaciones habituales

### Entrar a un contenedor

```bash
TASK=$(aws ecs list-tasks --cluster lab3-lc-dev-cluster \
  --service-name lab3-lc-dev-mysql --query 'taskArns[0]' --output text)

aws ecs execute-command --cluster lab3-lc-dev-cluster --task $TASK \
  --container mysql --interactive --command "/bin/bash"
```

### Entrar a una instancia EC2

```bash
aws ssm start-session --target <instance-id>
```

### Redesplegar MySQL tras cambiar su task definition

El servicio ignora `task_definition` por `lifecycle` — necesario para que el pipeline no
genere drift permanente en el frontend, pero significa que un cambio hecho desde
Terraform en MySQL no se despliega solo:

```bash
terraform apply -replace=module.ecs_service_mysql.aws_ecs_service.this
```

### Ver logs

```bash
aws logs tail /ecs/lab3-lc-dev-frontend --follow
aws logs tail /ecs/lab3-lc-dev-mysql --follow
```

---

## Troubleshooting

`describe-tasks` es la **primera** parada, no la última:

```bash
aws ecs describe-tasks --cluster lab3-lc-dev-cluster --tasks <arn> \
  --query 'tasks[0].[lastStatus,stopCode,stoppedReason]'

aws ecs describe-tasks --cluster lab3-lc-dev-cluster --tasks <arn> \
  --query 'tasks[0].containers[0].reason'
```

| Síntoma | Causa habitual |
|---|---|
| `registeredContainerInstancesCount = 0` | El `user_data` no corrió, o falta la policy de instancia |
| `Failed to resolve fs-xxxx.efs...` | Los mount targets todavía no estaban listos. Se resolvió con un `depends_on` en el output del módulo `efs`; si vuelve, revisar que siga ahí |
| `RESOURCE:MEMORY` / `RESOURCE:ENI` | No hay lugar en las instancias. **No bajar `min_size` de 3**: con `t3.small` son 2 slots de task por instancia |
| `AccessDeniedException` al arrancar | Falta un permiso en el rol de **execution** (es el que resuelve los secretos), no en el de task |
| El sitio da 503 | La listener rule no encuentra targets sanos. Si el cuerpo dice "No hay regla de enrutamiento activa", el problema es la rule; si es el HTML de AWS, son los targets |
| `execute-command` falla | Falta el plugin de Session Manager, o `enable_execute_command` está en false |
| Build muere en fase `QUEUED` | El rol de CodeBuild no puede escribir sus logs. El log group real es `/aws/codebuild/<proyecto>`, con el prefijo `/aws` |
| `Bad substitution` en el buildspec | CodeBuild ejecuta cada comando con `/bin/sh` (dash), no bash. Nada de `${VAR:0:7}` ni otras bashisms |
| Deploy: `role does not have sufficient permissions to access ECS` | Al rol del pipeline le falta alguna de las siete acciones que pide el deploy provider — el mensaje no dice cuál |
| Las alarmas disparan y no llega el mail | La suscripción SNS quedó en `PendingConfirmation` |

---

## Bajar todo

```bash
terraform destroy
```

Se lleva el repositorio ECR con las imágenes adentro (`force_delete = true`), así que
al volver a levantar hay que **repetir el paso 3**.

---

## Los dos pasos manuales

El resto es todo código. Estos dos no se pueden automatizar y están acá a propósito:

1. **El push de la imagen `bootstrap`** (paso 3), por la dependencia circular
   imagen ↔ servicio.
2. **Autorizar la CodeStar Connection** en la consola (Fase 7): el handshake OAuth con
   GitHub no tiene API. Nace en `PENDING` y hay que aprobarla a mano una vez.

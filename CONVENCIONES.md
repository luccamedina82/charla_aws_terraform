# Convenciones — Desafío IaC (Lab 3)

Equipo: Lucca · Christian · Entrega: **jueves 27/08 10:30**

Este archivo se mergea en el **PR 0**, antes de escribir el primer `resource`.
Si algo acá no se cumple, el PR no se aprueba.

---

## 1. Repositorios

| Repo | Contenido | Rama que despliega |
|---|---|---|
| `charla_aws_terraform` | Todo el Terraform | `develop` (apply manual) |
| `charla_aws_app` | App Node.js + `Dockerfile` + `buildspec.yml` | `main` (dispara CodePipeline) |

Ambos privados, ambos compartidos con los mentores **desde el día 1**.

**Por qué separados**: si el Terraform vive junto a la app, un `terraform fmt` dispara
un build de Docker y un deploy a ECS. Además el repo de IaC necesita credenciales
casi-admin y el de la app solo push a ECR.

---

## 2. Estructura del repo de IaC

```
charla_aws_terraform/
├── .github/workflows/terraform-ci.yml
├── docs/          arquitectura.drawio · decisiones-modulos.md · runbook.md
├── backend/       solo el bucket de estado. State local, se corre una vez
├── environments/dev/
│                  backend.tf providers.tf versions.tf main.tf
│                  variables.tf outputs.tf locals.tf terraform.tfvars
└── modules/       network · security-groups · alb · dns · ecs-cluster
                   ecs-service · efs · ecr · ssm-parameters · notifications · cicd
```

**Reglas de módulos**

1. Ningún módulo declara `provider` ni `backend`. En `versions.tf` van
   `required_providers` **y** `required_version` (mismo valor que el root) —
   lo pide `tflint` (`terraform_required_version`, preset `recommended`) y no
   encontramos forma de desactivar esa regla puntual sin romper el resto del
   preset.
2. Todo módulo tiene: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md`.
3. El límite del módulo es el **ciclo de vida**, no el servicio de AWS
   (`ecs-cluster` incluye ASG + launch template + instance profile).
4. `ecs-service` es **uno solo**, invocado dos veces (frontend y mysql).
5. `environments/dev/main.tf` no tiene ni un `resource`. Solo `module` y `locals`.
6. `for_each` con mapas, nunca `count` para listas de recursos parecidos entre sí.
   **Excepción**: `count = var.x ? 1 : 0` está permitido como interruptor
   on/off de un recurso único (ej. un rol IAM condicional, un bloque de
   política condicional). Ahí un `for_each` sobre una clave inventada no suma
   claridad y complica renombrar el índice más adelante. La regla original
   apuntaba a evitar `count` en listas de recursos repetidos, no a prohibir
   interruptores 0/1. Decisión de equipo, PR `feature/efs` (Fase 4).
7. Toda `variable` lleva `type` y `description`. Todo `output`, `description`.

**Comunidad vs propio**

| Módulo | Origen | Motivo (va en `docs/decisiones-modulos.md`) |
|---|---|---|
| VPC | `terraform-aws-modules/vpc/aws` | Problema resuelto y sin diferenciación |
| ACM | comunidad (opcional) | La validación DNS come tiempo y no enseña nada nuevo |
| Resto | propios | Ahí vive la especificidad de la solución |

---

## 3. Nomenclatura

**Recursos AWS** — todo sale de `local.name_prefix = "lab3-lc-${var.environment}"`
→ `lab3-lc-dev-alb`, `lab3-lc-dev-frontend`.

⚠️ ALB y Target Group: **máximo 32 caracteres**, sin guion final.
⚠️ Buckets S3: nombre global, sufijar con `data.aws_caller_identity.current.account_id`.

**HCL** — `snake_case`. El recurso principal del módulo se llama `this`.
No repetir el tipo: `aws_ecs_cluster.this`, no `aws_ecs_cluster.ecs_cluster`.

**Tags** — por `default_tags` en el provider. A mano, solo `Name`.

```hcl
default_tags {
  tags = {
    Project     = "lab3-iac"
    Environment = var.environment
    Team        = "lucca-christian"
    ManagedBy   = "terraform"
    Repo        = "charla_aws_terraform"
  }
}
```

---

## 4. Git

| Rama | Significa | Se aplica desde acá |
|---|---|---|
| `feature/*` | Trabajo en curso. CI corre `fmt`, `validate`, `tflint`, `plan` | Nunca |
| `develop` | El entorno `dev` real | Sí |
| `main` | Lo desplegado **y verificado**. Es el entregable | Nunca directo |

**Regla que da sentido a `main`**: se mergea `develop` → `main` solo cuando
`terraform plan` contra la infra viva devuelve **"No changes"**.

Sin `release/*` ni `hotfix/*`: no hay versiones paralelas ni producción que parchear.

**Nombres de rama** — kebab-case con el módulo adelante:
`feature/network-vpc-subnets`, `fix/alb-target-group-32-chars`, `docs/decisiones-modulos`

**Commits** — Conventional Commits: `feat(alb): listener 443 con redirect desde 80`

**Merge** — squash a `develop`, `--no-ff` a `main`. Tag en cada hito: `v0.2-ecs`.

**PR** — 1 approval obligatorio del otro. Nadie aprueba lo que no entendió: si algo
no queda claro se pregunta **en el PR**, y esa conversación queda escrita.
La presentación es individual — el review cruzado es el único mecanismo que garantiza
que los dos puedan defender todo el código.

**Protección de ramas**: verificar que el plan de GitHub la habilite en repos privados.
Si no, acuerdo explícito + `CODEOWNERS`.

---

## 5. Estado y trabajo en paralelo

- **Un solo state** para `environments/dev`. `backend/` aparte, con state local.
- Backend S3 con `use_lockfile = true` (lock nativo, sin DynamoDB — lo pide el enunciado).
- **No se aplica de a dos.** El lock hace fallar limpio al segundo, pero igual se avisa
  por Slack antes de cada `apply`.
- `.terraform.lock.hcl` **va commiteado**. Si uno usa WSL y el otro Windows nativo,
  correr una vez:
  `terraform providers lock -platform=linux_amd64 -platform=windows_amd64`
- `.gitignore`: `.terraform/`, `*.tfstate*`, `*.tfvars` (salvo `.example`), `crash.log`

---

## 6. Decisiones ya tomadas (no rediscutir, sí documentar)

| Decisión | Por qué |
|---|---|
| `lifecycle { ignore_changes = [task_definition, desired_count] }` en `aws_ecs_service` | El pipeline registra revisiones nuevas de la task def; sin esto Terraform hace drift permanente |
| Secretos por bloque `secrets` + `valueFrom`, no `environment` | Llega igual como variable de entorno al contenedor, pero la task definition solo guarda el ARN |
| Imagen `bootstrap` en ECR antes del apply completo | El servicio ECS no alcanza steady state sin imagen. Va en `runbook.md` |
| CodeStar Connection autorizada a mano en consola | El handshake OAuth con GitHub no es automatizable. Es *la* excepción al "sin consola" |
| OIDC con dos roles: read-only para `plan`, escritura para `apply` | Un PR no debe poder aplicar. Trust policy con el `sub` exacto de CloudTrail |
| MySQL en contenedor sobre EFS, no RDS | Lo pide el enunciado. En producción: RDS Multi-AZ |

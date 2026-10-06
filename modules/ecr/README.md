# Módulo `ecr`

Un repositorio ECR para la imagen de la trivia, con escaneo al push y una
política de ciclo de vida que acota cuántas imágenes se acumulan.

## Por qué existe como fase propia

El servicio ECS no llega a *steady state* si la imagen que referencia su task
definition no existe todavía. Como la task definition la crea Terraform y la
imagen la construye el pipeline, hay una dependencia circular. Se rompe
pusheando a mano una imagen con tag `bootstrap` **antes** del apply del
servicio (Fase 2 del `PLAN-FASES.md`, paso documentado en `docs/runbook.md`).

## Uso

```hcl
module "ecr" {
  source = "../../modules/ecr"

  name_prefix = local.name_prefix
}
```

## La política de ciclo de vida

ECR evalúa las reglas por `rulePriority` ascendente y **cada imagen queda
reclamada por la primera regla que la identifica**: las reglas de prioridad
más baja ya no pueden expirarla ([doc de AWS][lp], ejemplo *Filtering on all
images / Example B*).

| # | Identifica | Acción |
|---|---|---|
| 1 | tags `bootstrap*` | Conserva las 2 más recientes |
| 2 | sin tag | Expira a los 3 días |
| 3 | todas (catch-all) | Conserva las 10 más recientes |

La regla 1 casi nunca expira nada. Está para **reservar** las imágenes
`bootstrap` y que la regla 3 no pueda tocarlas: sin ella, 10 builds del
pipeline dejarían a la Fase 9 (destroy + apply desde cero) sin imagen con la
que arrancar.

[lp]: https://docs.aws.amazon.com/AmazonECR/latest/userguide/lifecycle_policy_examples.html

## Variables

| Nombre | Tipo | Default | Descripción |
|---|---|---|---|
| `name_prefix` | `string` | — | Prefijo de nombrado del root. El repo se llama `<prefix>-app` |
| `image_tag_mutability` | `string` | `"MUTABLE"` | `MUTABLE` para poder re-pushear `bootstrap` |
| `scan_on_push` | `bool` | `true` | Escaneo de vulnerabilidades al recibir la imagen |
| `force_delete` | `bool` | `true` | Permite destruir el repo con imágenes adentro (Fase 9) |
| `bootstrap_image_count` | `number` | `2` | Imágenes `bootstrap*` que se conservan |
| `untagged_retention_days` | `number` | `3` | Días que sobrevive una imagen sin tag |
| `max_image_count` | `number` | `10` | Imágenes que conserva la regla catch-all |

## Outputs

| Nombre | Descripción |
|---|---|
| `repository_url` | Destino del `docker push` y base de la imagen en la task definition |
| `repository_arn` | Para acotar la policy de CodeBuild (Fase 7) |
| `repository_name` | Para `aws ecr list-images` y el `imagedefinitions.json` |
| `registry_id` | Para `aws ecr get-login-password` |

## Los bloques `moved`

El recurso principal se llamaba `aws_ecr_repository.app` y pasó a `.this`, por
`CONVENCIONES.md` §3. Para Terraform **un rename no es un rename**: destruye
el recurso con la dirección vieja y crea otro con la nueva. Con
`force_delete = true`, eso se lleva el repositorio con las imágenes adentro —
incluida la `bootstrap`, sin la cual el servicio ECS no alcanza steady state.

Los dos bloques `moved` del final de `main.tf` reescriben la dirección en el
state sin tocar nada en AWS. Verificado con un `plan` contra el state real: el
repositorio aparece como `will be updated in-place`, no como replace.

Se pueden borrar cuando el apply con el rename ya haya corrido en `dev`.

## Decisiones de lab vs. producción

| Acá | En producción |
|---|---|
| `force_delete = true` | `false` — borrar un repo con imágenes es irreversible |
| `image_tag_mutability = "MUTABLE"` | `IMMUTABLE` — cada tag es un artefacto que no se reescribe |
| Sin `aws_ecr_repository_policy` | Policy explícita si otra cuenta tiene que tirar `pull` |
| Sin cifrado con KMS propio | `encryption_configuration` con CMK si lo pide el compliance |

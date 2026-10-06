# backend

Crea el bucket S3 que aloja el state remoto de `environments/dev`.

Es un **root module**, no un módulo reusable: es la única parte del repo que
declara `provider` (excepción explícita a la regla de CONVENCIONES §2.1).

## Por qué existe

`environments/dev` guarda su state en S3, pero ese bucket lo tiene que crear
alguien. Terraform no puede crear el backend donde va a guardar su propio state
en el mismo apply: es un problema del huevo y la gallina. Se resuelve con un
root module aparte, de state **local**, que se corre una sola vez.

## Cómo se corre

> Lo corre **una sola persona, una sola vez**. Correrlo dos veces desde otra
> máquina falla: el bucket ya existe y S3 devuelve `BucketAlreadyOwnedByYou`.

```bash
cd backend
terraform init
terraform plan
terraform apply
```

Salida esperada: `bucket_name`, `bucket_region` y `account_id`. Esos tres valores
van a `environments/dev/backend.tf` y a la sección *Estado actual* de `CLAUDE.md`.

El perfil de AWS sale de `AWS_PROFILE`. Para forzar otro:
`terraform apply -var="aws_profile=mi-perfil"`.

## El state de este directorio es local

`backend/terraform.tfstate` queda en disco y **no se commitea**
(`.gitignore`: `*.tfstate`). Es la única copia.

Si se pierde, no hace falta recrear nada — se reimporta:

```bash
terraform import aws_s3_bucket.this <nombre-del-bucket>
terraform import aws_s3_bucket_versioning.this <nombre-del-bucket>
terraform import aws_s3_bucket_server_side_encryption_configuration.this <nombre-del-bucket>
terraform import aws_s3_bucket_public_access_block.this <nombre-del-bucket>
```

## Decisiones

| Decisión | Por qué |
|---|---|
| Sufijo `account_id` en el nombre | El namespace de S3 es global; sin sufijo colisiona con cualquier otra cuenta |
| `versioning` habilitado | Un state corrupto o un apply a medias se recuperan volviendo a la versión anterior |
| `force_destroy = false` + `prevent_destroy = true` | El bucket guarda el state de toda la infra. Sin esto, un `destroy` acá se lleva el historial completo sin avisar |
| SSE-S3 (`AES256`) | El state guarda en texto plano todo lo que Terraform lee, incluida la password de MySQL resuelta desde SSM. KMS agregaría manejo de claves sin beneficio para un lab |
| Public access block | El state expone IDs, ARNs y secretos de toda la cuenta |
| Sin DynamoDB | El lock lo hace S3 nativo (`use_lockfile = true` en el backend de dev). Lo pide el enunciado |

## Teardown

El bucket está protegido por partida doble y **no se destruye con un
`terraform destroy` normal** — es intencional. Para bajarlo de verdad:

1. Destruir primero `environments/dev` (si no, su state queda huérfano).
2. Vaciar el bucket, incluidas las versiones anteriores:
   `aws s3api delete-objects` sobre `list-object-versions`.
3. Sacar el bloque `lifecycle { prevent_destroy = true }` de `main.tf`.
4. `terraform destroy`.

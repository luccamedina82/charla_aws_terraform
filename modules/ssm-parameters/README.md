# Módulo `ssm-parameters`

Crea los 6 parámetros de SSM que consumen las dos tasks (frontend en Fase 5,
mysql en Fase 4), según `estado-actual.md` §9.

## `db_user` no puede ser `"root"`

La imagen oficial `mysql:8.0` valida en su entrypoint que `MYSQL_USER` no sea
`"root"` y aborta el arranque si lo es — ese nombre está reservado para
`MYSQL_ROOT_PASSWORD`, que ya se crea aparte en este módulo
(`db_root_password`). El `default` en `environments/dev/variables.tf` es
`"rootlab3"`, elegido justamente para esquivar esa validación. Si se cambia
`var.db_user` más adelante, evitar el valor literal `"root"` — cualquier otro
nombre funciona, no hace falta tocar este módulo ni `ecs-service`.

## Estrategia de passwords

Opción **(a)** de `estado-actual.md` §10: `random_password` de Terraform. Los
cuatro secretos (`db_password`, `db_root_password`, `admin_password`, `token_secret`) se generan acá
y quedan en el state — que está en `s3://lab3-lc-tfstate-104981180500` cifrado
del lado del servidor y **no se commitea** (`.gitignore` ya excluye
`*.tfstate*`). No hay paso manual en el runbook para esto.

Si en algún momento se quiere rotar una password sin tocar el resto del
código: `terraform taint module.ssm_parameters.random_password.db_password`
antes del siguiente `apply`.

## Naming

Paths fijos por convención de la app (`SPEC-APP.md` §2 / `estado-actual.md` §9):

| Parámetro | Path |
|---|---|
| Host | `/lab3/<environment>/db/host` |
| Nombre de la base | `/lab3/<environment>/db/name` |
| Usuario | `/lab3/<environment>/db/user` |
| Password | `/lab3/<environment>/db/password` |
| Root password | `/lab3/<environment>/db/root_password` |
| Password del panel de admin | `/lab3/<environment>/app/admin_password` |
| Secreto de los tokens de admin | `/lab3/<environment>/app/token_secret` |

`db_host` se compone como `"mysql.${var.namespace_name}"` — nunca una IP,
según remarca `SPEC-APP.md` §7 y el error del Workshop 4 citado en
`PLAN-FASES.md` Fase 4.

## Inputs / Outputs

Ver `variables.tf` y `outputs.tf`. `parameter_arns` es el mapa que consume
`ecs-service` para armar el bloque `secrets` de la task definition (nunca
`environment`, por convención — la task definition solo guarda el ARN).

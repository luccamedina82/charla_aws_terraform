# Módulo `cicd`

Pipeline completo: push a `main` del repo de la app → build → push a ECR →
deploy a ECS. Según el plan de `estado-actual.md` §14.

## Qué crea

```
aws_s3_bucket.artifacts + public access block
aws_codestarconnections_connection.github        (nace PENDING)
aws_iam_role.codebuild + policy inline
aws_codebuild_project.this
aws_iam_role.codepipeline + policy inline
aws_codepipeline.this                            (Source → Build → Deploy)
aws_codestarnotifications_notification_rule.pipeline
```

## Paso manual insalvable: autorizar la Connection

`aws_codestarconnections_connection.github` nace en estado `PENDING`. El
handshake OAuth con GitHub no es automatizable desde Terraform — hay que
entrar a la consola de AWS (`Developer Tools → Settings → Connections`),
abrir la connection y clickear "Update pending connection" para autorizarla
contra la cuenta de GitHub. Sin este paso, el pipeline nunca dispara. Es la
segunda de las dos excepciones al "sin consola" del proyecto (la primera fue
la Connection en general, que ya estaba anotada; esta es la confirmación).

Verificar el estado después:

```bash
aws codestar-connections get-connection --connection-arn <connection_arn> \
  --query "Connection.ConnectionStatus"
```

Tiene que decir `"AVAILABLE"`, no `"PENDING"`.

## El deploy provider ECS y el blue/green: resuelto que sí

`aws_ecs_service.this` (módulo `ecs-service`, invocación frontend) trae
`deployment_configuration { strategy = "BLUE_GREEN" }`. La duda que señalaban
`estado-actual.md` §7 y §14 era si el deploy provider **ECS** de CodePipeline
—que solo hace `RegisterTaskDefinition` + `UpdateService` con
`imagedefinitions.json`— dispara ese blue/green, o si hacía falta el provider
especial `CodeDeployToECS`.

**Verificado en el primer pipeline real: lo dispara.** La estrategia vive a
nivel del servicio, así que a ECS le alcanza con el `UpdateService` para
aplicarla; el provider no necesita saber nada de blue/green
(`estado-actual.md` §15).

**Fallback, que no hizo falta**: si en algún momento dejara de comportarse
así, cambiar en la invocación del frontend (`environments/dev/main.tf`) el
`blue_green` a `null`, con lo que el servicio queda en rolling con
`deployment_circuit_breaker`. Es un cambio de una línea en la invocación, no
en este módulo ni en `ecs-service`.

## `iam:PassRole` acotado

El deploy provider ECS necesita pasar los roles de execution y de task del
frontend al registrar la nueva revisión de la task definition. El permiso
está acotado a esos dos ARN puntuales (`var.frontend_execution_role_arn`,
`var.frontend_task_role_arn`) con la condición `iam:PassedToService =
ecs-tasks.amazonaws.com` — no es un `iam:PassRole` sobre `"*"`.

Los dos ARN salen de los outputs `execution_role_arn` y `task_role_arn` de
`ecs-service`, que el root ya le pasa a este módulo desde la invocación del
frontend.

## El tag de la imagen

No lo genera este módulo — sale del `buildspec.yml`, que **vive en el repo de
la app** (`charla_aws_app`), no acá. Lee `$CONTAINER_NAME` (inyectada por
este módulo vía `var.container_name`) y `$REPOSITORY_URI` como variables de
entorno de CodeBuild. Formato del tag: fecha UTC + 7 caracteres del commit
(`estado-actual.md` §14), no el SHA solo — corrige lo que decía
`PLAN-FASES.md` originalmente.

Ojo con la sintaxis: CodeBuild ejecuta el buildspec con `/bin/sh`, no con
bash. `${VAR:0:7}` es expansión de bash y falla con `Bad substitution`, que
fue uno de los cuatro errores de la Fase 7 (`estado-actual.md` §15).

## Notificaciones

`aws_codestarnotifications_notification_rule.pipeline` es más simple que
armar una regla de EventBridge a mano: CodeStar Notifications ya sabe
traducir los eventos de CodePipeline (`succeeded`/`failed`) a un mensaje
legible en SNS. El permiso de publicación al topic para el principal
`codestar-notifications.amazonaws.com` lo agrega el módulo `notifications`
(`aws_sns_topic_policy`), no este módulo — sin eso, la notification rule
queda creada pero no entrega nada, y falla en silencio (no tira error de
Terraform).

## Inputs / Outputs

Ver `variables.tf` y `outputs.tf`. Casi todos los inputs son outputs de otros
módulos ya aplicados (`ecr`, `ecs_cluster`, `ecs_service_frontend`,
`notifications`) — este módulo no inventa nombres de recursos, los consume.

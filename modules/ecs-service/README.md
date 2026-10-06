# Módulo `ecs-service`

Módulo genérico invocado **dos veces**: mysql (Fase 4) y frontend (Fase 5), sin
tocarlo entre una invocación y la otra (`PLAN-FASES.md` / `CONVENCIONES.md`
§2.4). Lo que cambia entre ambas se resuelve con variables `object` que son
`null` por defecto y bloques `dynamic`.

## Qué crea

```
aws_cloudwatch_log_group.this
aws_iam_role.task_execution + policy attachment + policy inline (condicional)
aws_iam_role.task                      (vacío)
aws_ecs_task_definition.this
aws_service_discovery_service.this     (condicional, var.service_discovery)
aws_ecs_service.this
```

## Diferencias entre invocaciones

| | mysql (Fase 4) | frontend (Fase 5) |
|---|---|---|
| `load_balancer` | `null` | objeto con el target group |
| `service_discovery` | objeto (Cloud Map) | `null` |
| `efs_volume` | objeto (`/var/lib/mysql`) | `null` |
| `ordered_placement_strategies` | `[]` | `spread` × AZ + instancia |
| `container_image` | espejo AWS de mysql:8.0 | imagen del ECR propio |
| `desired_count` | `1` | `2` |
| `task_cpu` / `task_memory` | `256` / `512` (ver más abajo) | a definir en Fase 5 |

## Sizing de la task de mysql

No estaba especificado en `SPEC-APP.md` ni en `PLAN-FASES.md`. Se usó
**256 CPU units / 512 MB de memoria**:

- Las instancias del cluster son `t3.small` (2 vCPU / 2 GiB), con 3 registradas
  (`estado-actual.md` §5) → sobra margen para este tamaño sin comprometer el
  slot de ENIs que también necesita el frontend.
- `mysql:8.0` arranca cómodo con 512 MB para un dataset de lab (6 productos +
  pedidos de una demo de ~15 minutos).
- Si en la Fase 9 (prueba de reproducibilidad) el arranque de mysql tarda
  demasiado o se ve memory-constrained, subir primero memoria a 1024 antes que
  CPU — mysqld es más sensible a memoria que a CPU en cargas chicas.

Es una asunción razonable, no un valor verificado contra carga real; queda
documentado acá para poder revisarlo con criterio si hace falta ajustarlo.

## Sobre `lifecycle.ignore_changes`

`estado-actual.md` §10 señala que `ignore_changes` no acepta condicionales
(`var.x ? [...] : []`). Se optó por ignorar `task_definition` y `desired_count`
**en las dos invocaciones por igual** — mysql no tiene pipeline propio que le
registre revisiones nuevas, así que no le hace daño tenerlo también, y evita
partir el recurso en dos variantes del módulo.

## `count` en interruptores condicionales

El módulo usa `count = var.x ? 1 : 0` en tres lugares (`task_execution_secrets`,
`task_exec_command`, `aws_service_discovery_service.this`) — todos son
recursos únicos que existen o no, no listas de recursos parecidos. Por
decisión de equipo (PR `feature/efs`, Fase 4) esto es una excepción explícita
a `CONVENCIONES.md` §2.6, que ya quedó documentada ahí: la regla apunta a
evitar `count` en listas de recursos repetidos, no a prohibir interruptores
0/1 de un recurso condicional. Un `for_each` con una clave inventada para
esto no suma claridad y, si el módulo ya está aplicado, cambiar `this[0]` por
`this["clave"]` obliga a un bloque `moved` sin ganar nada a cambio.

## ECS Exec (`enable_execute_command`)

Habilitado por default (`true`). Es lo que permite verificar la persistencia
de datos del "Listo cuando" de la Fase 4 sin pasar por Session Manager + la
instancia EC2 + `docker exec`:

```bash
aws ecs execute-command --cluster lab3-lc-dev-cluster \
  --task <task-arn> --container mysql --interactive \
  --command "mysql -u root -p<pass> -e 'SELECT ...'"
```

Requiere que el agente ECS de la instancia esté actualizado — la AMI AL2023
del cluster ya trae una versión compatible, no hace falta tocar nada del
`launch template`. El permiso (`ssmmessages:*Channel`) va en el rol de
**task**, no en el de execution: el canal lo abre el agente que corre dentro
del contenedor en runtime, no el proceso que resuelve secrets antes de
arrancar.

## Rol de ejecución vs rol de task

`task_execution` es el que resuelve los `secrets` (SSM) **antes** de que el
contenedor arranque — es el que necesita `ssm:GetParameters` y `kms:Decrypt`.
`task` es el que usa la app en runtime vía el SDK — acá queda vacío porque,
según `SPEC-APP.md`, la app no llama a APIs de AWS. Confundir estos dos roles
da un error que parece de red (`estado-actual.md` §9).

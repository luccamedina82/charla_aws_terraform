# Módulo `efs`

Crea el EFS que usa la task de MySQL para persistir datos entre reemplazos de task
(Fase 4, `PLAN-FASES.md`).

## Qué crea

- `aws_efs_file_system.this` — encriptado en reposo. Sin políticas de backup
  (`aws_efs_backup_policy`) porque es un lab con dato descartable; en producción
  iría `ENABLED`.
- `aws_efs_mount_target.this` — uno por subnet privada (una por AZ), `for_each`
  sobre `var.private_subnet_ids`, como pide `CONVENCIONES.md` §2.6 (`for_each`
  con mapas/sets, nunca `count` para esto).
- `aws_efs_access_point.this` — fuerza `uid/gid 999` y monta en `/mysql` dentro
  del filesystem.

## Asunciones a verificar si algo cambia

- **uid/gid 999**: es el usuario `mysql` en la imagen oficial `mysql:8.0` (base
  Debian). Si en algún momento se cambia de imagen base, confirmar con:
  `docker run --rm <imagen> id mysql` y ajustar acá.
- El SG (`efs_sg_id`) ya existe y está aplicado (`sg-0aeb1a39536193392` en
  `estado-actual.md` §5) — este módulo no crea reglas de security group, solo
  las consume.

## Inputs / Outputs

Ver `variables.tf` y `outputs.tf`. `access_point_id` y `file_system_id` los
consume el módulo `ecs-service` para armar el `volume` de la task definition de
mysql.

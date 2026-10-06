locals {
  family = "${var.name_prefix}-${var.name}"
}

data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${local.family}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.family}-logs"
  }
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# --- Rol de EJECUCIÓN: actúa antes de que el contenedor arranque, resuelve
# los secrets. No confundir con el rol de task (CONVENCIONES.md / estado-actual.md §9).
resource "aws_iam_role" "task_execution" {
  name               = "${local.family}-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = {
    Name = "${local.family}-exec-role"
  }
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "task_execution_secrets" {
  count = length(var.secrets) > 0 ? 1 : 0

  statement {
    sid       = "ReadSecretsFromSsm"
    actions   = ["ssm:GetParameters"]
    resources = [for s in var.secrets : s.valueFrom]
  }

  statement {
    sid       = "DecryptSecureStrings"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    # La clave de SSM es administrada por AWS y su ARN varía por cuenta, por
    # eso resources sigue en "*". Esta condición acota el permiso real: solo
    # descifrados que vengan de SSM, no cualquier clave KMS de la cuenta.
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${data.aws_region.current.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "task_execution_secrets" {
  count  = length(var.secrets) > 0 ? 1 : 0
  name   = "${local.family}-secrets"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_secrets[0].json
}

# --- Rol de TASK: lo usa el código de la app en runtime. Vacío a propósito
# (SPEC-APP.md: la app no llama a APIs de AWS). Se deja creado para no tener
# que agregarlo después si eso cambia.
resource "aws_iam_role" "task" {
  name               = "${local.family}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json

  tags = {
    Name = "${local.family}-task-role"
  }
}

# Habilita el canal de ECS Exec. El agente que abre el canal corre dentro de
# la task, por eso este permiso va en el rol de TASK, no en el de execution.
data "aws_iam_policy_document" "task_exec_command" {
  count = var.enable_execute_command ? 1 : 0

  statement {
    sid = "EcsExecChannels"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_exec_command" {
  count  = var.enable_execute_command ? 1 : 0
  name   = "${local.family}-exec-command"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_exec_command[0].json
}

resource "aws_ecs_task_definition" "this" {
  family                   = local.family
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = var.name
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        for e in var.environment_variables : {
          name  = e.name
          value = e.value
        }
      ]

      secrets = [
        for s in var.secrets : {
          name      = s.name
          valueFrom = s.valueFrom
        }
      ]

      mountPoints = var.efs_volume == null ? [] : [
        {
          sourceVolume  = "efs-data"
          containerPath = var.efs_volume.container_path
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = var.name
        }
      }
    }
  ])

  dynamic "volume" {
    for_each = var.efs_volume == null ? [] : [var.efs_volume]

    content {
      name = "efs-data"

      efs_volume_configuration {
        file_system_id     = volume.value.file_system_id
        transit_encryption = "ENABLED"

        authorization_config {
          access_point_id = volume.value.access_point_id
          iam             = "DISABLED"
        }
      }
    }
  }

  tags = {
    Name = local.family
  }
}

# Condicional: solo mysql (Fase 4) trae service_discovery != null.
resource "aws_service_discovery_service" "this" {
  count = var.service_discovery == null ? 0 : 1

  name = var.name

  dns_config {
    namespace_id = var.service_discovery.namespace_id

    dns_records {
      ttl  = var.service_discovery.dns_ttl
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  # Sin bloque health_check_custom_config a proposito. Un bloque vacio no se
  # envia a la API (AWS devuelve HealthCheckCustomConfig = null), pero Terraform
  # lo ve en el codigo y propone agregarlo en cada plan; como es inmutable,
  # fuerza el reemplazo del servicio de Cloud Map una y otra vez.
  #
  # Con ECS service discovery no hace falta: es ECS quien registra y da de baja
  # las instancias segun el estado de la task, sin que Cloud Map chequee nada.

  # Sin esto, el destroy de la Fase 9 falla si quedan instancias registradas
  # en el servicio (la task todavía "presente" en Cloud Map al momento del
  # destroy). force_destroy las borra antes de eliminar el servicio.
  force_destroy = true

  tags = {
    Name = "${local.family}-discovery"
  }
}

resource "aws_ecs_service" "this" {
  name            = local.family
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  enable_execute_command = var.enable_execute_command

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider_name
    weight            = 1
    base              = 0
  }

  network_configuration {
    subnets         = var.subnet_ids
    security_groups = var.security_group_ids
  }

  # Solo tiene sentido detras de un balanceador: es el margen que se le da a la
  # task para arrancar antes de que el target group empiece a marcarla unhealthy.
  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  # En blue/green el rollback lo maneja la propia estrategia; los dos mecanismos
  # juntos se pisan.
  dynamic "deployment_circuit_breaker" {
    for_each = var.blue_green == null ? [1] : []

    content {
      enable   = true
      rollback = true
    }
  }

  dynamic "deployment_configuration" {
    for_each = var.blue_green == null ? [] : [var.blue_green]

    content {
      strategy             = "BLUE_GREEN"
      bake_time_in_minutes = deployment_configuration.value.bake_time_in_minutes
    }
  }

  dynamic "load_balancer" {
    for_each = var.load_balancer == null ? [] : [var.load_balancer]

    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = coalesce(load_balancer.value.container_name, var.name)
      container_port   = var.container_port

      # Lo que ECS necesita para mover el trafico: el segundo target group y el
      # ARN de la listener RULE. No alcanza la default action del listener,
      # porque lo que ECS reescribe es una rule.
      dynamic "advanced_configuration" {
        for_each = var.blue_green == null ? [] : [var.blue_green]

        content {
          alternate_target_group_arn = advanced_configuration.value.alternate_target_group_arn
          production_listener_rule   = advanced_configuration.value.production_listener_rule_arn
          test_listener_rule         = advanced_configuration.value.test_listener_rule_arn
          role_arn                   = advanced_configuration.value.role_arn
        }
      }
    }
  }

  dynamic "service_registries" {
    for_each = var.service_discovery == null ? [] : [1]

    content {
      registry_arn = aws_service_discovery_service.this[0].arn
    }
  }

  dynamic "ordered_placement_strategy" {
    for_each = var.ordered_placement_strategies

    content {
      type  = ordered_placement_strategy.value.type
      field = ordered_placement_strategy.value.field
    }
  }

  # El pipeline registra revisiones nuevas de la task def (CONVENCIONES.md §6);
  # sin ignorar esto, Terraform hace drift permanente. Se aplica igual en las
  # dos invocaciones (mysql y frontend) porque lifecycle no acepta
  # condicionales sobre var.* (estado-actual.md §10) — mysql no sufre por
  # tenerlo también.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  tags = {
    Name = local.family
  }
}

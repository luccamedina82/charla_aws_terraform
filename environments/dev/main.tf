# Punto de entrada del entorno dev.
#
# Acá van solo bloques module, locals y data — nunca un resource. Si hace falta
# un resource suelto, es que falta un módulo (CONVENCIONES §2.5).

module "network" {
  source = "../../modules/network"

  name_prefix = local.name_prefix
}

module "security_groups" {
  source = "../../modules/security-groups"

  name_prefix = local.name_prefix
  vpc_id      = module.network.vpc_id
}

module "ecr" {
  source      = "../../modules/ecr"
  name_prefix = local.name_prefix
}

# --- Fase 5/6: HTTPS ---------------------------------------------------------
#
# Va acá y no al final del archivo a propósito: la Fase 4 agrega sus modulos al
# final, y separar las dos regiones deja que git auto-mergee las dos ramas.

# La hosted zone ya existe en la cuenta; no la crea Terraform.
data "aws_route53_zone" "this" {
  name         = var.hosted_zone_name
  private_zone = false
}

module "acm" {
  source = "../../modules/acm"

  domain_name    = var.domain_name
  hosted_zone_id = data.aws_route53_zone.this.zone_id
}

module "alb" {
  source = "../../modules/alb"

  name_prefix       = local.name_prefix
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  alb_sg_id         = module.security_groups.alb_sg_id
  certificate_arn   = module.acm.certificate_arn
}

module "dns" {
  source = "../../modules/dns"

  hosted_zone_id = data.aws_route53_zone.this.zone_id
  domain_name    = var.domain_name
  alb_dns_name   = module.alb.alb_dns_name
  alb_zone_id    = module.alb.alb_zone_id
}

module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  name_prefix        = local.name_prefix
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  instance_sg_id     = module.security_groups.cluster_sg_id

  # Sin el modulo de observabilidad no hay nada que consuma estas metricas, y
  # se cobran aparte.
  container_insights = "disabled"
}

# --- Fase 4: EFS + MySQL + SSM ---------------------------------------------
# Agregar al final de environments/dev/main.tf. Usa solo module/locals, sin
# resource, como pide CONVENCIONES.md §2.5. Los nombres module.network,
# module.security_groups y module.ecs_cluster son los que ya existen
# (estado-actual.md §6) — si en el repo real difieren, ajustar las
# referencias de abajo, no la lógica.

module "efs" {
  source = "../../modules/efs"

  name_prefix        = local.name_prefix
  private_subnet_ids = module.network.private_subnet_ids
  efs_sg_id          = module.security_groups.efs_sg_id
}

module "ssm_parameters" {
  source = "../../modules/ssm-parameters"

  environment    = var.environment
  name_prefix    = local.name_prefix
  namespace_name = module.ecs_cluster.namespace_name
  db_name        = var.db_name
  db_user        = var.db_user
}

module "ecs_service_mysql" {
  source = "../../modules/ecs-service"

  name                   = "mysql"
  name_prefix            = local.name_prefix
  cluster_id             = module.ecs_cluster.cluster_id
  capacity_provider_name = module.ecs_cluster.capacity_provider_name
  subnet_ids             = module.network.private_subnet_ids
  security_group_ids     = [module.security_groups.mysql_sg_id]

  task_cpu        = 256
  task_memory     = 512
  container_image = "public.ecr.aws/docker/library/mysql:8.4"
  container_port  = 3306
  desired_count   = 1

  environment_variables = [
    { name = "MYSQL_DATABASE", value = var.db_name },
  ]

  secrets = [
    { name = "MYSQL_USER", valueFrom = module.ssm_parameters.parameter_arns["db_user"] },
    { name = "MYSQL_PASSWORD", valueFrom = module.ssm_parameters.parameter_arns["db_password"] },
    { name = "MYSQL_ROOT_PASSWORD", valueFrom = module.ssm_parameters.parameter_arns["db_root_password"] },
  ]

  efs_volume = {
    file_system_id  = module.efs.file_system_id
    access_point_id = module.efs.access_point_id
    container_path  = "/var/lib/mysql"
  }

  service_discovery = {
    namespace_id = module.ecs_cluster.namespace_id
  }
}

# --- Fase 5: servicio frontend ----------------------------------------------

module "ecs_service_frontend" {
  source = "../../modules/ecs-service"

  name                   = "frontend"
  name_prefix            = local.name_prefix
  cluster_id             = module.ecs_cluster.cluster_id
  capacity_provider_name = module.ecs_cluster.capacity_provider_name
  subnet_ids             = module.network.private_subnet_ids
  security_group_ids     = [module.security_groups.frontend_sg_id]

  task_cpu        = 256
  task_memory     = 512
  container_image = "${module.ecr.repository_url}:${var.frontend_image_tag}"
  # La trivia corre como USER node: sin root no puede abrir puertos < 1024.
  container_port = 8080
  desired_count  = var.frontend_desired_count

  # La app lee DB_*, ADMIN_PASSWORD y TOKEN_SECRET del entorno. Van todas por el bloque secrets y
  # no por environment: llegan igual como variable de entorno, pero la task
  # definition guarda el ARN del parametro en vez del valor.
  #
  # DB_HOST vale "mysql.lab3.local", compuesto en el modulo ssm-parameters a
  # partir del namespace de Cloud Map. No hay forma de que quede una IP.
  secrets = [
    { name = "DB_HOST", valueFrom = module.ssm_parameters.parameter_arns["db_host"] },
    { name = "DB_NAME", valueFrom = module.ssm_parameters.parameter_arns["db_name"] },
    { name = "DB_USER", valueFrom = module.ssm_parameters.parameter_arns["db_user"] },
    { name = "DB_PASSWORD", valueFrom = module.ssm_parameters.parameter_arns["db_password"] },
    { name = "ADMIN_PASSWORD", valueFrom = module.ssm_parameters.parameter_arns["admin_password"] },
    { name = "TOKEN_SECRET", valueFrom = module.ssm_parameters.parameter_arns["token_secret"] },
  ]

  load_balancer = {
    target_group_arn = module.alb.target_group_arn
  }

  blue_green = {
    alternate_target_group_arn   = module.alb.alternate_target_group_arn
    production_listener_rule_arn = module.alb.production_listener_rule_arn
    role_arn                     = module.alb.load_balancer_role_arn
    bake_time_in_minutes         = 2
  }

  # Margen para que Node levante antes de que el target group la evalue.
  health_check_grace_period_seconds = 60

  # Primero reparte entre AZ y despues entre instancias, en ese orden: dos tasks
  # en la misma AZ sobreviven a un contenedor caido, no a una AZ caida.
  ordered_placement_strategies = [
    { type = "spread", field = "attribute:ecs.availability-zone" },
    { type = "spread", field = "instanceId" },
  ]
}

# --- Fase 7: CI/CD -----------------------------------------------------
# Ajustar el nombre del
# module block del frontend si no es "ecs_service_frontend" en tu repo real.

module "notifications" {
  source = "../../modules/notifications"

  name_prefix         = local.name_prefix
  subscription_emails = var.notification_emails
}

module "cicd" {
  source = "../../modules/cicd"

  name_prefix        = local.name_prefix
  github_owner       = "luccamedina82"
  github_repo        = "charla_aws_app"
  branch             = "main"
  ecr_repository_url = module.ecr.repository_url
  ecr_repository_arn = module.ecr.repository_arn
  cluster_name       = module.ecs_cluster.cluster_name

  # Ajustar el nombre del module block si difiere.
  frontend_service_name       = module.ecs_service_frontend.service_name
  frontend_execution_role_arn = module.ecs_service_frontend.execution_role_arn
  frontend_task_role_arn      = module.ecs_service_frontend.task_role_arn

  notifications_topic_arn = module.notifications.topic_arn
}

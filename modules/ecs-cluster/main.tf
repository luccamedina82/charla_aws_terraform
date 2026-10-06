# ---------------------------------------------------------------------------
# Cluster ECS en modo EC2: cluster + capacidad (ASG) + namespace de Cloud Map.
#
# El límite del módulo es el ciclo de vida, no el servicio de AWS: el ASG, el
# launch template y el instance profile no tienen sentido por separado, y el
# namespace es uno solo para todo el cluster (si viviera en ecs-service, la
# segunda invocación intentaría crear un namespace duplicado).
# ---------------------------------------------------------------------------

# AMI ECS-optimized, por data source y no hardcodeada: AWS publica una nueva
# cada pocas semanas y un ami-xxxx fijo deja de existir en unos meses.
data "aws_ssm_parameter" "ecs_ami" {
  name = var.ecs_ami_ssm_parameter
}

# El ASG no hereda default_tags del provider: aws_autoscaling_group no expone
# tags_all, solo bloques tag. Sin esto, el ASG y las instancias serían los
# únicos recursos del proyecto sin etiquetar. Es una limitación del recurso,
# no una excepción a CONVENCIONES §3.
data "aws_default_tags" "current" {}

locals {
  # El value del parámetro viene marcado como sensible y el plan mostraría
  # "(sensitive value)" en lugar del AMI ID — justo el dato que hay que mirar
  # en el diff cuando AWS publica una imagen nueva. Un ID de AMI pública no es
  # un secreto.
  ecs_ami_id = nonsensitive(data.aws_ssm_parameter.ecs_ami.value)
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = var.container_insights
  }

  tags = {
    Name = "${var.name_prefix}-cluster"
  }
}

# ---------------------------------------------------------------------------
# IAM de las instancias
#
# Un rol no se puede asociar a una EC2 directamente: necesita un instance
# profile que lo envuelva. La consola lo crea sin mostrarlo.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "instance_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name_prefix}-ecs-instance-role"
  assume_role_policy = data.aws_iam_policy_document.instance_assume_role.json

  tags = {
    Name = "${var.name_prefix}-ecs-instance-role"
  }
}

# Sin esta policy la instancia arranca, pasa el health check del ASG y nunca
# se registra en el cluster: el agente no puede llamar a la API de ECS.
resource "aws_iam_role_policy_attachment" "instance_ecs" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Sin esta, no hay Session Manager. Es la única forma de entrar a una instancia
# en subnet privada sin bastion ni llave SSH, y es donde se debuggea cuando una
# task no arranca.
resource "aws_iam_role_policy_attachment" "instance_ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name_prefix}-ecs-instance-profile"
  role = aws_iam_role.instance.name

  tags = {
    Name = "${var.name_prefix}-ecs-instance-profile"
  }
}

# ---------------------------------------------------------------------------
# Launch template
# ---------------------------------------------------------------------------
resource "aws_launch_template" "this" {
  name_prefix   = "${var.name_prefix}-ecs-"
  image_id      = local.ecs_ami_id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.this.arn
  }

  vpc_security_group_ids = [var.instance_sg_id]

  # ESTA es la línea que separa "3 EC2 en un ASG" de "un cluster ECS". Sin
  # ella el agente no sabe a qué cluster unirse, las instancias quedan sanas
  # para el ASG y registeredContainerInstancesCount se queda en 0.
  user_data = base64encode(<<-EOT
    #!/bin/bash
    echo "ECS_CLUSTER=${aws_ecs_cluster.this.name}" >> /etc/ecs/ecs.config
  EOT
  )

  metadata_options {
    http_endpoint = "enabled"

    # IMDSv2 obligatorio: sin token no se responde. Cierra la puerta al SSRF
    # que lee credenciales desde 169.254.169.254.
    http_tokens = "required"

    # 2 saltos porque el primero lo consume la red del contenedor. Con 1, un
    # contenedor que necesite IMDS recibe un timeout sin explicación.
    http_put_response_hop_limit = var.imds_hop_limit
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Las instancias las tagea el ASG por propagate_at_launch; acá solo los
  # volúmenes, que esa propagación no alcanza.
  tag_specifications {
    resource_type = "volume"

    tags = {
      Name = "${var.name_prefix}-ecs-instance-root"
    }
  }

  tags = {
    Name = "${var.name_prefix}-ecs-lt"
  }

  # Un cambio de AMI crea la versión nueva antes de destruir la vieja, para no
  # dejar al ASG sin plantilla en el medio.
  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Auto Scaling Group
# ---------------------------------------------------------------------------
resource "aws_autoscaling_group" "this" {
  name                = "${var.name_prefix}-ecs-asg"
  vpc_zone_identifier = var.private_subnet_ids

  # min_size = 3 no es un capricho de disponibilidad, es el colchón de ENIs.
  # Con awsvpc cada task consume una ENI y una t3.small tiene 3 (una es de la
  # instancia): 2 slots por instancia, 6 en total. En régimen corren 3 tasks
  # (2 frontend + 1 mysql) y durante un swap blue/green son 5.
  #
  # Ojo antes de bajarlo a 2: el managed scaling del capacity provider calcula
  # cuántas instancias hacen falta para las tasks actuales y con 3 tasks
  # concluiría que alcanzan 2 instancias. Este piso es lo que se lo impide.
  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  health_check_type = "EC2"

  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  # Tiene que coincidir con managed_termination_protection del capacity
  # provider. Si no coinciden, el apply falla con un mensaje que no menciona
  # la relación entre los dos.
  protect_from_scale_in = var.managed_termination_protection

  dynamic "tag" {
    for_each = merge(
      data.aws_default_tags.current.tags,
      {
        Name = "${var.name_prefix}-ecs-instance"

        # ECS agrega este tag por su cuenta al asociar el ASG a un capacity
        # provider — con managed termination protection o sin ella. Tiene que
        # estar en el código aunque no lo pongamos nosotros: si falta, cada
        # plan posterior propone borrarlo, y el "No changes" que pide el DoD
        # no llega nunca.
        AmazonECSManaged = ""
      }
    )

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

# ---------------------------------------------------------------------------
# Capacity provider
#
# Lo que la consola mostraba en una sola pantalla son tres recursos: el
# provider que envuelve al ASG, la asociación con el cluster, y la referencia
# desde cada servicio (esa vive en el módulo ecs-service).
# ---------------------------------------------------------------------------
resource "aws_ecs_capacity_provider" "this" {
  name = "${var.name_prefix}-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.this.arn

    # Apagada a propósito: exige protect_from_scale_in en el ASG y después el
    # destroy de la Fase 9 se traba con instancias protegidas que hay que
    # desproteger a mano. Para un lab con prueba de reproducibilidad
    # obligatoria, el costo supera al beneficio.
    managed_termination_protection = var.managed_termination_protection ? "ENABLED" : "DISABLED"

    # Drena las tasks antes de terminar una instancia en vez de matarlas.
    managed_draining = "ENABLED"

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = var.capacity_provider_target
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 2
      instance_warmup_period    = 300
    }
  }

  tags = {
    Name = "${var.name_prefix}-cp"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = [aws_ecs_capacity_provider.this.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    weight            = 1
    base              = 0
  }
}

# ---------------------------------------------------------------------------
# Cloud Map
#
# Crea una hosted zone privada en la VPC. Cuando el servicio de MySQL se
# registre, mysql.<namespace> va a resolver a la IP de la task viva — y va a
# seguir resolviendo cuando ECS la reemplace por otra con otra IP.
# ---------------------------------------------------------------------------
resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = var.namespace_name
  description = "Service discovery del cluster ${aws_ecs_cluster.this.name}"
  vpc         = var.vpc_id

  tags = {
    Name = var.namespace_name
  }
}

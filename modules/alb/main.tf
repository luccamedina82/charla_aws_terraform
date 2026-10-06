# ---------------------------------------------------------------------------
# ALB con dos target groups, preparado para el blue/green nativo de ECS.
#
# La forma de este módulo la impone el deployment: ECS no mueve el tráfico
# reescribiendo la default action del listener, sino una listener RULE. Por eso
# acá hay una rule explícita y el listener 443 tiene una default action que no
# sirve tráfico. Con un solo target group y sin rule, blue/green no se puede.
# ---------------------------------------------------------------------------

locals {
  # lab3-lc-dev son 11 caracteres. -fe-green son 9 más: 20 de 32.
  blue_name  = "${var.name_prefix}-fe-blue"
  green_name = "${var.name_prefix}-fe-green"
}

resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [var.alb_sg_id]

  enable_deletion_protection = var.enable_deletion_protection

  # Descarta headers HTTP mal formados en vez de pasarlos al backend.
  drop_invalid_header_fields = true

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}

# ---------------------------------------------------------------------------
# Target groups
#
# Dos, no uno: blue sirve producción y green recibe la versión nueva durante un
# deployment. ECS los va alternando, así que cuál es cuál cambia con cada
# deploy — los nombres son etiquetas de posición, no de contenido.
#
# target_type = "ip" porque con awsvpc cada task tiene su propia ENI y se
# registra por IP. Con "instance" se registraría el puerto de la EC2, que en
# awsvpc no existe.
# ---------------------------------------------------------------------------
resource "aws_lb_target_group" "blue" {
  name        = local.blue_name
  port        = var.target_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = local.blue_name
  }
}

resource "aws_lb_target_group" "green" {
  name        = local.green_name
  port        = var.target_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = local.green_name
  }
}

# ---------------------------------------------------------------------------
# Listeners
# ---------------------------------------------------------------------------

# El 80 no sirve nada: solo manda a HTTPS. 301 y no 302 para que el navegador
# y los intermediarios lo cacheen.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = {
    Name = "${var.name_prefix}-listener-http"
  }
}

# La default action devuelve 503 a propósito: el tráfico real lo sirve la
# listener rule de abajo, que es la que ECS reescribe en cada blue/green. Si el
# forward viviera acá, ECS no tendría qué mover.
#
# Un 503 en producción significa que la rule desapareció.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "No hay regla de enrutamiento activa"
      status_code  = "503"
    }
  }

  tags = {
    Name = "${var.name_prefix}-listener-https"
  }
}

# Esta rule es la que sirve el sitio. ECS le cambia el target group entre blue y
# green durante el deployment, por eso su ARN es lo que consume el módulo
# ecs-service en advanced_configuration.production_listener_rule.
#
# ignore_changes en la acción: después del primer blue/green la rule apunta al
# target group contrario al que dice el código. Sin esto, cada plan propondría
# devolverla a blue — drift permanente y, peor, un cambio de tráfico por afuera
# del deployment.
resource "aws_lb_listener_rule" "production" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  tags = {
    Name = "${var.name_prefix}-rule-produccion"
  }

  lifecycle {
    ignore_changes = [action]
  }
}

# ---------------------------------------------------------------------------
# Rol que ECS asume para reescribir la listener rule
#
# Es un requisito del blue/green nativo: sin este rol, ECS no puede tocar el
# balanceador y el deployment falla al momento de mover el tráfico, no antes.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_lb_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_lb" {
  name               = "${var.name_prefix}-ecs-lb-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_lb_assume_role.json

  tags = {
    Name = "${var.name_prefix}-ecs-lb-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_lb" {
  role       = aws_iam_role.ecs_lb.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers"
}

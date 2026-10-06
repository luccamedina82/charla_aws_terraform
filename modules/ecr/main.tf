# ---------------------------------------------------------------------------
# Repositorio ECR para la imagen de la trivia (repo luccamedina82/charla_aws_app).
#
# Rompe la dependencia circular imagen <-> servicio ECS: el repo existe y
# recibe la imagen `bootstrap` antes de que la Fase 5 cree el servicio, que
# sin una imagen que traer nunca llegaria a steady state.
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  name                 = "${var.name_prefix}-app"
  image_tag_mutability = var.image_tag_mutability

  # true para que el destroy de la Fase 9 no falle con imagenes adentro.
  # En produccion iria false: borrar un repo con imagenes es irreversible.
  force_delete = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # El resto de los tags los inyecta default_tags del provider (CONVENCIONES 3).
  tags = {
    Name = "${var.name_prefix}-app"
  }
}

# ---------------------------------------------------------------------------
# Ciclo de vida de las imagenes.
#
# ECR evalua las reglas por rulePriority ascendente y cada imagen queda
# "reclamada" por la primera regla que la identifica: las reglas posteriores
# ya no pueden expirarla. Ese detalle es el que hace que el orden importe.
#
# Por eso la regla 1 identifica las imagenes bootstrap aunque casi nunca las
# expire: al reclamarlas, la regla 3 (catch-all) no puede borrarlas. Sin ese
# orden, 10 builds del pipeline dejarian a la Fase 9 sin imagen con la que
# levantar de cero.
# ---------------------------------------------------------------------------
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Reserva las imagenes bootstrap y conserva las ${var.bootstrap_image_count} mas recientes"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["bootstrap*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.bootstrap_image_count
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Elimina imagenes sin tag despues de ${var.untagged_retention_days} dias"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_retention_days
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 3
        description  = "Conserva las ${var.max_image_count} imagenes mas recientes del pipeline"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_image_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Renombrado de .app a .this (CONVENCIONES §3).
#
# Para Terraform un rename no es un rename: destruye el recurso con la
# dirección vieja y crea otro con la nueva. Con force_delete = true eso se
# llevaría el repositorio y las imágenes que tenga adentro, incluida la
# bootstrap de la que depende el arranque del servicio ECS.
#
# Estos bloques reescriben la dirección en el state sin tocar nada en AWS.
# Verificado con un plan contra el state real: el repositorio sale como
# "will be updated in-place", no como replace.
#
# Se pueden borrar cuando el apply con el rename haya corrido en dev, que es
# el único entorno que existe.
# ---------------------------------------------------------------------------
moved {
  from = aws_ecr_repository.app
  to   = aws_ecr_repository.this
}

moved {
  from = aws_ecr_lifecycle_policy.app
  to   = aws_ecr_lifecycle_policy.this
}

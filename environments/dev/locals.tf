locals {
  # Todo nombre de recurso del entorno sale de acá.
  # "lab3-lc-dev" son 11 caracteres: deja 21 libres antes del tope de 32
  # que imponen el ALB y el Target Group.
  name_prefix = "lab3-lc-${var.environment}"
}

# Estrategia de passwords: opción (a) de estado-actual.md §10 — random_password.
# El valor queda en el state, que está en S3 cifrado (SSE) y no se commitea.
# Es la opción más simple y defendible para un lab; la alternativa (crear el
# parámetro con lifecycle.ignore_changes = [value] y cargar el valor a mano)
# suma un paso manual al runbook que acá no hace falta.

resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "db_root_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "admin_password" {
  length  = 20
  special = false
}

# Firma los tokens de admin. Tiene que ser el mismo en todas las tasks: si
# falta, cada task genera el suyo y el login funciona o no segun a que task
# mande el ALB.
resource "random_password" "token_secret" {
  length  = 64
  special = false
}

resource "aws_ssm_parameter" "db_host" {
  name  = "/lab3/${var.environment}/db/host"
  type  = "String"
  value = "mysql.${var.namespace_name}"

  tags = {
    Name = "${var.name_prefix}-ssm-db-host"
  }
}

resource "aws_ssm_parameter" "db_name" {
  name  = "/lab3/${var.environment}/db/name"
  type  = "String"
  value = var.db_name

  tags = {
    Name = "${var.name_prefix}-ssm-db-name"
  }
}

# Usuario de aplicación de la trivia (default "trivia" en environments/dev,
# ver variables.tf del root). No puede valer literalmente "root": la imagen
# oficial de MySQL rechaza MYSQL_USER=root en su entrypoint (ese nombre está
# reservado para MYSQL_ROOT_PASSWORD) y el contenedor no arranca.
resource "aws_ssm_parameter" "db_user" {
  name  = "/lab3/${var.environment}/db/user"
  type  = "String"
  value = var.db_user

  tags = {
    Name = "${var.name_prefix}-ssm-db-user"
  }
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/lab3/${var.environment}/db/password"
  type  = "SecureString"
  value = random_password.db_password.result

  tags = {
    Name = "${var.name_prefix}-ssm-db-password"
  }
}

resource "aws_ssm_parameter" "db_root_password" {
  name  = "/lab3/${var.environment}/db/root_password"
  type  = "SecureString"
  value = random_password.db_root_password.result

  tags = {
    Name = "${var.name_prefix}-ssm-db-root-password"
  }
}

resource "aws_ssm_parameter" "admin_password" {
  name  = "/lab3/${var.environment}/app/admin_password"
  type  = "SecureString"
  value = random_password.admin_password.result

  tags = {
    Name = "${var.name_prefix}-ssm-admin-password"
  }
}

resource "aws_ssm_parameter" "token_secret" {
  name  = "/lab3/${var.environment}/app/token_secret"
  type  = "SecureString"
  value = random_password.token_secret.result

  tags = {
    Name = "${var.name_prefix}-ssm-token-secret"
  }
}

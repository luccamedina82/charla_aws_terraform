# Reglas core de Terraform (plugin bundleado, no se descarga).
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Reglas específicas de AWS: tipos de instancia inexistentes, argumentos
# inválidos, nombres que exceden el límite del servicio (ej: ALB/TG > 32 chars).
plugin "aws" {
  enabled = true
  version = "0.48.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

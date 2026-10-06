output "parameter_arns" {
  description = "Mapa nombre-lógico -> ARN. El bloque secrets de la task definition referencia el ARN, no el valor."
  value = {
    db_host          = aws_ssm_parameter.db_host.arn
    db_name          = aws_ssm_parameter.db_name.arn
    db_user          = aws_ssm_parameter.db_user.arn
    db_password      = aws_ssm_parameter.db_password.arn
    db_root_password = aws_ssm_parameter.db_root_password.arn
    admin_password   = aws_ssm_parameter.admin_password.arn
    token_secret     = aws_ssm_parameter.token_secret.arn
  }
}

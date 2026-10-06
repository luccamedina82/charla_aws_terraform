variable "aws_region" {
  description = "Región de AWS donde se despliega el entorno"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Perfil de AWS CLI. null = toma AWS_PROFILE del entorno. Debe quedar en null cuando el pipeline asume el rol por OIDC"
  type        = string
  default     = null
}

variable "hosted_zone_name" {
  description = "Hosted zone de Route 53 que ya existe en la cuenta (se crea a mano, fuera de Terraform, y se delega desde tekforge.site). El certificado y el alias se crean adentro de ella"
  type        = string
  default     = "charla.tekforge.site"
}

variable "domain_name" {
  description = "FQDN publico del sitio. Tiene que estar dentro de hosted_zone_name. Va en el apex de la zona delegada: el alias de Route 53 funciona ahi y un CNAME no podria"
  type        = string
  default     = "charla.tekforge.site"
}

variable "frontend_image_tag" {
  description = "Tag de la imagen del frontend en ECR. Queda en bootstrap: a partir del primer deploy el pipeline registra revisiones nuevas de la task definition y el servicio las ignora por lifecycle"
  type        = string
  default     = "bootstrap"
}

variable "frontend_desired_count" {
  description = "Tasks del frontend. 2 para que el spread las reparta entre las dos AZ"
  type        = number
  default     = 2
}

variable "environment" {
  description = "Nombre del entorno. Alimenta local.name_prefix y el tag Environment"
  type        = string
  default     = "dev"
}

variable "db_name" {
  type        = string
  description = "Nombre de la base de datos de la app (MYSQL_DATABASE / DB_NAME de la trivia)."
  default     = "trivia"
}

variable "db_user" {
  type        = string
  description = "Usuario de aplicación de la trivia (MYSQL_USER / DB_USER). ADVERTENCIA: con 'root' el contenedor de MySQL no arranca — ver README de modules/ssm-parameters."
  default     = "trivia"
}

variable "notification_emails" {
  type        = list(string)
  description = "Emails suscriptos al SNS de notificaciones del pipeline."
  default     = ["luccamedina03@gmail.com"]
}

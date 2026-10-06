variable "environment" {
  type        = string
  description = "Nombre del environment (dev), usado en el path /lab3/<environment>/... de cada parámetro."
}

variable "name_prefix" {
  type        = string
  description = "Prefijo de nombres del proyecto, usado en el tag Name de cada parámetro."
}

variable "namespace_name" {
  type        = string
  description = "Nombre del namespace de Cloud Map (module.ecs_cluster.namespace_name, ej. lab3.local). Compone DB_HOST como mysql.<namespace_name>."
}

variable "db_name" {
  type        = string
  description = "Nombre de la base de datos. Alimenta DB_NAME (frontend) y MYSQL_DATABASE (mysql)."
}

variable "db_user" {
  type        = string
  description = "Usuario de aplicación para mysqli. Alimenta DB_USER (frontend) y MYSQL_USER (mysql)."
}

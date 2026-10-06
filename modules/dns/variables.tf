variable "hosted_zone_id" {
  description = "Hosted zone de Route 53 donde crear el registro. Ya existe en la cuenta: no la administra Terraform"
  type        = string
}

variable "domain_name" {
  description = "FQDN publico del sitio. Tiene que estar dentro de la hosted zone"
  type        = string
}

variable "alb_dns_name" {
  description = "DNS del ALB al que apunta el alias"
  type        = string
}

variable "alb_zone_id" {
  description = "Zone ID del ALB, que no es el de nuestra hosted zone: cada region tiene el suyo y AWS lo expone como atributo del balanceador"
  type        = string
}

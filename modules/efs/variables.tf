variable "name_prefix" {
  type        = string
  description = "Prefijo de nombres del proyecto (local.name_prefix del root, ej. lab3-lc-dev)."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "IDs de las subnets privadas (una por AZ) donde crear un mount target."
}

variable "efs_sg_id" {
  type        = string
  description = "Security group que permite 2049 desde el SG de mysql (module.security_groups.efs_sg_id)."
}

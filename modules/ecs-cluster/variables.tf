variable "name_prefix" {
  description = "Prefijo de nombrado, calculado una sola vez en el root (local.name_prefix)"
  type        = string
}

variable "vpc_id" {
  description = "ID de la VPC. Lo necesita el namespace de Cloud Map, que crea una hosted zone privada asociada a ella"
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas donde el ASG lanza las instancias. Una por AZ: de acá sale la distribución del cluster"
  type        = list(string)
}

variable "instance_sg_id" {
  description = "Security group de las instancias del cluster. Sin inbound: con awsvpc el tráfico de las tasks entra por la ENI de la task, no por la de la instancia"
  type        = string
}

variable "instance_type" {
  description = "Tipo de instancia del ASG. Con awsvpc cada task consume una ENI de la instancia, así que el límite de ENIs del tipo es el techo de tasks por instancia"
  type        = string
  default     = "t3.small"

  # t3.micro y compañía tienen 2 ENIs: una para la instancia y UNA sola para
  # tasks. Con 3 instancias serían 3 slots, menos que las tasks que corremos.
  # Es el incidente del Lab 2, convertido en un error de plan.
  validation {
    condition     = !contains(["t2.nano", "t2.micro", "t3.nano", "t3.micro", "t3a.nano", "t3a.micro", "t4g.nano", "t4g.micro"], var.instance_type)
    error_message = "Ese tipo de instancia tiene solo 2 ENIs, o sea 1 task awsvpc por instancia. Usar t3.small o mayor."
  }
}

variable "min_size" {
  description = "Mínimo de instancias del ASG. Es el piso que impide que el managed scaling del capacity provider compacte el cluster y deje sin ENIs libres al deployment blue/green"
  type        = number
  default     = 3
}

variable "desired_capacity" {
  description = "Instancias que el ASG intenta mantener. A partir del primer apply lo maneja el capacity provider"
  type        = number
  default     = 3
}

variable "max_size" {
  description = "Techo de instancias del ASG. Acota el gasto si el managed scaling se dispara"
  type        = number
  default     = 6
}

variable "root_volume_size" {
  description = "Tamaño en GiB del disco raíz de cada instancia. Ahí se acumulan las imágenes que baja el agente ECS"
  type        = number
  default     = 30
}

variable "namespace_name" {
  description = "Nombre del namespace de Cloud Map. Define el FQDN de MySQL: mysql.<namespace_name>, que es el valor de DB_HOST"
  type        = string
  default     = "lab3.local"
}

variable "container_insights" {
  description = "Container Insights del cluster. 'enhanced' cuesta varias veces más que 'enabled' y acá no aporta: los servicios son dos"
  type        = string
  default     = "enabled"

  validation {
    condition     = contains(["enabled", "enhanced", "disabled"], var.container_insights)
    error_message = "container_insights debe ser enabled, enhanced o disabled."
  }
}

variable "imds_hop_limit" {
  description = "Saltos de red permitidos a la respuesta de IMDSv2. 2 es lo que recomienda la doc de ECS para que un contenedor pueda alcanzar el metadata de la instancia; 1 es más restrictivo y alcanza si ningún contenedor lo necesita"
  type        = number
  default     = 2
}

variable "managed_termination_protection" {
  description = "Deja que el capacity provider proteja de scale-in a las instancias con tasks. Requiere protect_from_scale_in en el ASG y complica el destroy de la Fase 9, por eso está apagado"
  type        = bool
  default     = false
}

variable "capacity_provider_target" {
  description = "Porcentaje de uso del cluster que persigue el managed scaling. 100 = sin capacidad ociosa; el colchón lo da min_size, no este número"
  type        = number
  default     = 100
}

variable "ecs_ami_ssm_parameter" {
  description = "Parámetro público de SSM del que sale la AMI ECS-optimized. El sufijo /image_id devuelve el ID solo; sin él el parámetro trae un JSON que habría que decodificar"
  type        = string
  default     = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

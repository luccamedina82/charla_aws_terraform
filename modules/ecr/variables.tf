variable "name_prefix" {
  description = "Prefijo de nombrado, calculado una sola vez en el root (local.name_prefix)"
  type        = string
}

variable "image_tag_mutability" {
  description = "MUTABLE permite re-pushear el tag bootstrap sin borrarlo primero. IMMUTABLE seria lo correcto en produccion, donde cada tag es un artefacto inmutable"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability debe ser MUTABLE o IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Dispara el escaneo de vulnerabilidades al recibir cada imagen"
  type        = bool
  default     = true
}

variable "force_delete" {
  description = "Permite destruir el repositorio con imagenes adentro. Requisito de la prueba de reproducibilidad (Fase 9); en produccion iria false"
  type        = bool
  default     = true
}

variable "bootstrap_image_count" {
  description = "Cuantas imagenes con tag bootstrap* se conservan. Ademas de limitarlas, la regla las reserva para que la regla catch-all no pueda expirarlas"
  type        = number
  default     = 2

  validation {
    condition     = var.bootstrap_image_count >= 1
    error_message = "bootstrap_image_count debe ser al menos 1: sin imagen bootstrap el servicio ECS no alcanza steady state."
  }
}

variable "untagged_retention_days" {
  description = "Dias que sobrevive una imagen sin tag. Se generan cada vez que el pipeline reusa un tag y dejan de referenciar la capa anterior"
  type        = number
  default     = 3
}

variable "max_image_count" {
  description = "Cuantas imagenes conserva la regla catch-all. Acota el costo de almacenamiento sin borrar el historial reciente de deploys"
  type        = number
  default     = 10
}

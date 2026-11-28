variable "environment" {
  description = "Ambiente de despliegue"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment debe ser dev o prod."
  }
}

variable "bucket_prefix" {
  description = "Prefijo del nombre del bucket; Terraform le agrega el account_id"
  type        = string
  default     = "mi-proyecto"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.bucket_prefix)) && length(var.bucket_prefix) <= 45
    error_message = "bucket_prefix solo puede contener minúsculas, números y guiones (máximo 45 caracteres)."
  }
}
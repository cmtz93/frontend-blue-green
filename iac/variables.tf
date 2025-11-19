variable "aws_region" {
  description = "Región principal para los recursos (ej: us-east-1 para CloudFront global)"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo para nombrar recursos (ej: mi-frontend)"
  type        = string
}

variable "domain_name" {
  description = "Dominio completo del sitio (ej: www.midominio.com)"
  type        = string
}

variable "hosted_zone_id" {
  description = "ID de la Zona Hosted de Route 53 donde está el dominio"
  type        = string
}

variable "github_repo_owner" {
  description = "Dueño del repo GitHub (Organización o Usuario)"
  type        = string
}

variable "github_repo_name" {
  description = "Nombre del repositorio en GitHub"
  type        = string
}
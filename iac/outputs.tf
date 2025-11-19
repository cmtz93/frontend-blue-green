# --- S3 Bucket (Para la subida de artefactos) ---
output "s3_bucket_name" {
  description = "El nombre del bucket S3 para configurar en la variable S3_BUCKET_NAME de GitHub"
  value       = aws_s3_bucket.frontend_bucket.id
}

# --- IAM Role (Para la autenticación OIDC) ---
output "github_actions_role_arn" {
  description = "El ARN del rol que GitHub Actions debe asumir (role-to-assume)"
  value       = aws_iam_role.github_deploy_role.arn
}

# --- CloudFront (Para el Swap y la Invalidación) ---
output "cloudfront_distribution_id" {
  description = "El ID de la distribución (ej. E123...) para la variable CF_DISTRIBUTION_ID"
  value       = aws_cloudfront_distribution.s3_distribution.id
}

output "cloudfront_domain_name" {
  description = "La URL pública del sitio web"
  value       = aws_cloudfront_distribution.s3_distribution.domain_name
}

# --- SSM Parameter Store (Para leer/escribir estado Blue/Green) ---
output "ssm_parameter_name" {
  description = "El nombre del parámetro SSM que guarda el estado (active-prefix)"
  value       = aws_ssm_parameter.active_env.name
}

# --- AWS Region (Para configurar el CLI) ---
output "aws_region" {
  description = "La región donde se desplegaron los recursos"
  value       = var.aws_region
}

# --- SNS (Para configurar la recepcion de alertas) ---
output "sns_alerts_topic_arn" {
  description = "ARN del tópico SNS para suscripciones de alarma (Lambda/Email)"
  value       = aws_sns_topic.alerts.arn
}

output "site_url" {
  description = "URL final del sitio"
  value       = "https://${var.domain_name}"
}
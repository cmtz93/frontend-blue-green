terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # CONFIGURACIÓN OBLIGATORIA DEL BACKEND
  backend "s3" {
    bucket         = "my-project-terraform-state"
    key            = "iac/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}

# Provider Principal
provider "aws" {
  region = var.aws_region
}

# Provider para recursos globales de CloudFront (Certificados deben estar en us-east-1)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# ==========================================
# 1. Gestión de Estado (Blue/Green)
# ==========================================
resource "aws_ssm_parameter" "active_env" {
  name        = "/deployment/${var.project_name}/active-prefix"
  description = "Entorno activo (blue o green). Modificado por GitHub Actions."
  type        = "String"
  value       = "blue" # Valor inicial

  # IMPORTANTE: Ignoramos cambios para que Terraform no revierta el despliegue
  lifecycle {
    ignore_changes = [value]
  }
}

# ==========================================
# 2. Seguridad y Certificados (ACM)
# ==========================================
resource "aws_acm_certificate" "cert" {
  provider          = aws.us_east_1
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => dvo
  }
  allow_overwrite = true
  name            = each.value.resource_record_name
  records         = [each.value.resource_record_value]
  ttl             = 60
  type            = each.value.resource_record_type
  zone_id         = var.hosted_zone_id
}

resource "aws_acm_certificate_validation" "cert" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ==========================================
# 3. Almacenamiento (S3)
# ==========================================
resource "aws_s3_bucket" "frontend_bucket" {
  bucket = "${var.project_name}-assets-${var.aws_region}"
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.frontend_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "block" {
  bucket = aws_s3_bucket.frontend_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.project_name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Política para permitir que CloudFront lea del bucket
resource "aws_s3_bucket_policy" "allow_cloudfront" {
  bucket = aws_s3_bucket.frontend_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFront"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.s3_distribution.arn
          }
        }
      }
    ]
  })
}

# ==========================================
# 4. Distribución (CloudFront)
# ==========================================
resource "aws_cloudfront_distribution" "s3_distribution" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.domain_name]

  origin {
    domain_name              = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name
    origin_id                = "S3Origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    target_origin_id       = "S3Origin"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    viewer_protocol_policy = "redirect-to-https"
    
    # Policies optimizadas por AWS
    cache_policy_id          = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf" # CORS-S3Origin

    # CONFIGURACIÓN CLAVE BLUE/GREEN
    origin_path = "/blue" 
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Ignoramos cambios en origin_path porque GitHub Actions lo controla
  lifecycle {
    ignore_changes = [
      default_cache_behavior[0].origin_path
    ]
  }
}

# ==========================================
# 5. DNS (Route 53)
# ==========================================
resource "aws_route53_record" "alias_record" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}
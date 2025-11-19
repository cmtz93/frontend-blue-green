# ==========================================
# Notificaciones (SNS)
# ==========================================
resource "aws_sns_topic" "alerts" {
  provider = aws.us_east_1
  name     = "${var.project_name}-alerts-topic"
}

# ==========================================
# Métricas Adicionales CloudFront
# ==========================================
resource "aws_cloudfront_monitoring_subscription" "extras" {
  distribution_id = aws_cloudfront_distribution.s3_distribution.id
  monitoring_subscription {
    realtime_metrics_subscription_config {
      realtime_metrics_subscription_status = "Enabled"
    }
  }
}

# ==========================================
# Alarmas Críticas
# ==========================================

# 1. Tasa de Errores 5xx > 5%
resource "aws_cloudwatch_metric_alarm" "high_5xx" {
  provider            = aws.us_east_1
  alarm_name          = "${var.project_name}-High-5xx-Error-Rate"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 60
  statistic           = "Average"
  threshold           = 5
  alarm_description   = "Error rate exceeds 5%"
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    DistributionId = aws_cloudfront_distribution.s3_distribution.id
    Region         = "Global"
  }
}

# 2. Latencia de Origen > 1s
resource "aws_cloudwatch_metric_alarm" "high_latency" {
  provider            = aws.us_east_1
  alarm_name          = "${var.project_name}-High-Origin-Latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "OriginLatency"
  namespace           = "AWS/CloudFront"
  period              = 60
  statistic           = "Average"
  threshold           = 1000
  alarm_description   = "Origin latency > 1000ms"
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DistributionId = aws_cloudfront_distribution.s3_distribution.id
    Region         = "Global"
  }
}
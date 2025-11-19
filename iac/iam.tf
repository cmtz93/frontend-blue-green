# ==========================================
# Configuración OIDC para GitHub Actions
# ==========================================
data "aws_iam_policy_document" "github_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo_owner}/${var.github_repo_name}:*"]
    }
  }
}

resource "aws_iam_role" "github_deploy_role" {
  name               = "${var.project_name}-github-deploy-role"
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json
}

# ==========================================
# Política de Permisos Mínimos
# ==========================================
data "aws_iam_policy_document" "github_deploy_policy" {
  
  # 1. Acceso a S3 (Subida y Limpieza)
  statement {
    sid    = "S3Access"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.frontend_bucket.arn,
      "${aws_s3_bucket.frontend_bucket.arn}/*",
    ]
  }

  # 2. Acceso a CloudFront (Swap e Invalidación)
  statement {
    sid    = "CloudFrontAccess"
    effect = "Allow"
    actions = [
      "cloudfront:UpdateDistribution",
      "cloudfront:GetDistributionConfig",
      "cloudfront:CreateInvalidation"
    ]
    resources = [aws_cloudfront_distribution.s3_distribution.arn]
  }

  # 3. Acceso a SSM (Leer/Escribir Estado)
  statement {
    sid    = "SSMAccess"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:PutParameter"
    ]
    resources = [aws_ssm_parameter.active_env.arn]
  }

  # 4. Archivar los releases inmutables
  statement {
    sid    = "S3ArchiveAccess"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.frontend_bucket.arn,
      "${aws_s3_bucket.frontend_bucket.arn}/releases/*", # Permite escribir en la carpeta /releases
    ]
  }
}

resource "aws_iam_policy" "github_deploy_policy" {
  name   = "${var.project_name}-github-policy"
  policy = data.aws_iam_policy_document.github_deploy_policy.json
}

resource "aws_iam_role_policy_attachment" "github_deploy_attach" {
  role       = aws_iam_role.github_deploy_role.name
  policy_arn = aws_iam_policy.github_deploy_policy.arn
}

data "aws_caller_identity" "current" {}
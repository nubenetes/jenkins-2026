# -----------------------------------------------------------------------------
# terraform/aws-managed-grafana is the AWS analogue of terraform/azure-managed-
# grafana: a one-time setup module that provisions the persistent AWS backend
# observability.mode == "managed-aws" uses, plus the Amazon Managed Grafana that
# visualizes it. Applied once by 01.04-aws-bootstrap.yml (GCS remote state),
# read by 02.01-gke-provision.yml to build the in-cluster secret.
#
# Architecture (Amazon Managed Grafana is a frontend; telemetry goes to AWS
# backends and Grafana reads them):
#   collector metrics -> Amazon Managed Service for Prometheus (remote-write, SigV4)
#   collector traces  -> AWS X-Ray
#   collector logs    -> CloudWatch Logs
#   Amazon Managed Grafana -> PROMETHEUS / XRAY / CLOUDWATCH data sources
#
# Auth from GKE (not AWS): the collector's ServiceAccount is federated to an IAM
# role via the cluster's OIDC issuer + AssumeRoleWithWebIdentity - no long-lived
# access keys (the AWS equivalent of the Azure Entra OIDC approach).
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --- Metrics: Amazon Managed Service for Prometheus --------------------------

resource "aws_prometheus_workspace" "this" {
  alias = "${var.name_prefix}-amp"
}

# --- Logs: CloudWatch log group ----------------------------------------------

resource "aws_cloudwatch_log_group" "collector" {
  name              = "/jenkins-2026/${var.name_prefix}/otel"
  retention_in_days = 30
}

# --- GKE OIDC federation: provider + collector role --------------------------

data "tls_certificate" "gke" {
  url = var.gke_oidc_issuer_url
}

resource "aws_iam_openid_connect_provider" "gke" {
  url             = var.gke_oidc_issuer_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.gke.certificates[0].sha1_fingerprint]
}

locals {
  oidc_host = replace(var.gke_oidc_issuer_url, "https://", "")
}

data "aws_iam_policy_document" "collector_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.gke.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:${var.collector_namespace}:${var.collector_service_account}"]
    }
  }
}

resource "aws_iam_role" "collector" {
  name               = "${var.name_prefix}-otel-collector"
  assume_role_policy = data.aws_iam_policy_document.collector_assume.json
}

data "aws_iam_policy_document" "collector" {
  statement {
    sid       = "AMPRemoteWrite"
    effect    = "Allow"
    actions   = ["aps:RemoteWrite", "aps:GetSeries", "aps:GetLabels", "aps:GetMetricMetadata"]
    resources = [aws_prometheus_workspace.this.arn]
  }
  statement {
    sid       = "XRay"
    effect    = "Allow"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"]
    resources = ["*"]
  }
  statement {
    sid       = "CloudWatchLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "logs:DescribeLogGroups"]
    resources = ["${aws_cloudwatch_log_group.collector.arn}:*"]
  }
}

resource "aws_iam_role_policy" "collector" {
  name   = "${var.name_prefix}-otel-collector"
  role   = aws_iam_role.collector.id
  policy = data.aws_iam_policy_document.collector.json
}

# --- Amazon Managed Grafana --------------------------------------------------

# Workspace role AMG assumes to read the data sources. With CURRENT_ACCOUNT
# access, the API requires CUSTOMER_MANAGED + an explicit role (SERVICE_MANAGED
# only auto-creates one via the console / an Organization with trusted access).
data "aws_iam_policy_document" "grafana_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["grafana.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "grafana" {
  name               = "${var.name_prefix}-grafana-workspace"
  assume_role_policy = data.aws_iam_policy_document.grafana_assume.json
}

resource "aws_iam_role_policy_attachment" "grafana" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonPrometheusQueryAccess",
    "arn:aws:iam::aws:policy/service-role/AmazonGrafanaCloudWatchAccess",
    "arn:aws:iam::aws:policy/AWSXrayReadOnlyAccess",
  ])
  role       = aws_iam_role.grafana.name
  policy_arn = each.value
}

resource "aws_grafana_workspace" "this" {
  name                     = "${var.name_prefix}-grafana"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "CUSTOMER_MANAGED"
  role_arn                 = aws_iam_role.grafana.arn
  grafana_version          = var.grafana_version
  data_sources             = ["PROMETHEUS", "XRAY", "CLOUDWATCH"]
}

# Workspace Admin users/groups are AWS_SSO identities granted in IAM Identity
# Center (Grafana workspace -> Configure users), not IAM roles - so they're
# managed outside Terraform. See README.md "GitHub Actions automation".

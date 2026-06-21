# These feed the in-cluster aws-managed-credentials Secret that 02.01-gke-
# provision.yml builds from the GCS state (read-only), consumed by
# observability/otel-collector/values-managed-aws*.yaml.

output "aws_region" {
  description = "AWS region -> AWS_REGION."
  value       = data.aws_region.current.name
}

output "amp_remote_write_endpoint" {
  description = "Amazon Managed Prometheus remote-write URL -> AMP_REMOTE_WRITE_ENDPOINT (prometheusremotewrite exporter, SigV4 to service aps)."
  value       = "${aws_prometheus_workspace.this.prometheus_endpoint}api/v1/remote_write"
}

output "amp_query_url" {
  description = "Amazon Managed Prometheus query base URL (Grafana PROMETHEUS data source)."
  value       = aws_prometheus_workspace.this.prometheus_endpoint
}

output "amp_workspace_id" {
  description = "Amazon Managed Prometheus workspace id."
  value       = aws_prometheus_workspace.this.id
}

output "collector_role_arn" {
  description = "IAM role the collector assumes via web identity -> AWS_ROLE_ARN."
  value       = aws_iam_role.collector.arn
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for collector logs -> AWS_CLOUDWATCH_LOG_GROUP."
  value       = aws_cloudwatch_log_group.collector.name
}

output "grafana_endpoint" {
  description = "Amazon Managed Grafana workspace URL -> GRAFANA_BASE_URL (banner link)."
  value       = "https://${aws_grafana_workspace.this.endpoint}"
}

output "grafana_workspace_id" {
  description = "Amazon Managed Grafana workspace id."
  value       = aws_grafana_workspace.this.id
}

output "dashboard_publisher_role_arn" {
  description = "IAM role 02.01-gke-provision assumes via GitHub OIDC to publish dashboards to AMG -> GitHub secret AWS_DASHBOARD_PUBLISH_ROLE_ARN."
  value       = aws_iam_role.dashboard_publisher.arn
}

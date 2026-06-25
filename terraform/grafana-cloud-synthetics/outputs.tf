output "check_jobs" {
  value       = keys(grafana_synthetic_monitoring_check.http)
  description = "Synthetic Monitoring HTTP check jobs created."
}

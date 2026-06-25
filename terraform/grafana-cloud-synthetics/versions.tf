terraform {
  required_version = ">= 1.9.0"
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
    }
  }
}

# Cloud provider: manages the Synthetic Monitoring installation on the stack.
provider "grafana" {
  cloud_access_policy_token = var.cloud_access_policy_token
}

# Synthetic Monitoring provider: configured from the installation output so check
# resources can be managed. Keyless — both tokens derive from the stack access policy.
provider "grafana" {
  alias           = "sm"
  sm_url          = grafana_synthetic_monitoring_installation.this.stack_sm_api_url
  sm_access_token = grafana_synthetic_monitoring_installation.this.sm_access_token
}

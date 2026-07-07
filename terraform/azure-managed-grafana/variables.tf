variable "subscription_id" {
  type        = string
  description = "Azure subscription ID the managed-azure observability resources are created in."
}

variable "tenant_id" {
  type        = string
  description = "Microsoft Entra (Azure AD) tenant ID. The collector authenticates to Azure Monitor managed Prometheus with a service principal in this tenant."
}

variable "resource_group_name" {
  type        = string
  default     = "jenkins-2026-observability"
  description = "Resource group for the managed-azure observability stack. Created by this module."
}

variable "location" {
  type        = string
  default     = "spaincentral"
  description = "Azure region for the telemetry backends (Azure Monitor workspace + DCE/DCR, Application Insights, Log Analytics) - the latency-critical ingestion path. Defaults to spaincentral (Madrid) to sit next to the GKE cluster in europe-southwest1."
}

variable "grafana_location" {
  type        = string
  default     = "francecentral"
  description = "Azure region for Azure Managed Grafana. AMG is NOT available in spaincentral, so it goes to the nearest region that has it (francecentral); it queries the spaincentral Azure Monitor workspace cross-region (UI latency is not critical). Both are EU regions (GDPR)."
}

variable "name_prefix" {
  type        = string
  default     = "jenkins-2026"
  description = "Prefix for resource names so they're easy to identify and don't collide."
}

variable "grafana_admin_object_ids" {
  type        = list(string)
  default     = []
  description = "Entra object IDs (users/groups) granted Grafana Admin on the Azure Managed Grafana instance. Empty = only the deployer keeps portal-level access."
}

variable "publish_app_client_id" {
  type        = string
  default     = ""
  description = "Client (app) ID of the dedicated low-privilege PUBLISH app registration (the AZURE_PUBLISH_CLIENT_ID GitHub secret). When set, this module also grants Grafana Admin to that app's service principal so Day1 / Day2.publish.* can publish dashboards/alerts as a scoped identity (Grafana Admin + Reader only) instead of the Contributor+UAA bootstrap app. Empty = single-app mode (only the apply principal keeps Grafana Admin). See docs/102 § Why the per-cloud asymmetry."
}

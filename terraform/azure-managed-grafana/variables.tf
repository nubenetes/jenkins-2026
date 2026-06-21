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
  default     = "westeurope"
  description = "Azure region for all resources (Azure Managed Grafana, Azure Monitor workspace, Application Insights, Log Analytics)."
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

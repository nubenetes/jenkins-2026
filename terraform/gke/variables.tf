variable "project_id" {
  type        = string
  description = "GCP project ID to create the throwaway GKE cluster in. Must have billing enabled."
}

variable "region" {
  type        = string
  description = "GCP region for the VPC/subnet."
  default     = "europe-southwest1"
}

variable "zone" {
  type        = string
  description = "GCP zone for the (zonal) GKE cluster and node pool."
  default     = "europe-southwest1-a"
}

variable "cluster_name" {
  type        = string
  description = "Name for the cluster, VPC, subnet and node service account."
  default     = "jenkins-2026"
}

variable "machine_type" {
  type        = string
  description = "Machine type for cluster nodes. e2-standard-8 (8 vCPU/32GB) provides ample headroom for Jenkins + Microservices pods + the OTel collectors plus multiple concurrent parallel build agent pods."
  default     = "e2-standard-8"
}

variable "node_count" {
  type        = number
  description = "Initial node count for the single node pool (autoscaling adjusts within min/max afterwards)."
  default     = 3
}

variable "min_node_count" {
  type        = number
  description = "Minimum nodes for cluster autoscaling."
  default     = 2
}

variable "max_node_count" {
  type        = number
  description = "Maximum nodes for cluster autoscaling (extra headroom for Jenkins build agent pods)."
  default     = 4
}

variable "enable_node_autoprovisioning" {
  type        = bool
  description = <<-EOT
    Enable GKE Node Auto-Provisioning (NAP) — the GA, Google-native equivalent of
    Karpenter. When true, the cluster auto-creates and deletes right-sized node pools
    (including Spot pools) on demand, driven by Custom ComputeClasses (see
    infrastructure/compute-classes/). The static "<cluster_name>-pool" still hosts the
    long-lived platform (ArgoCD/Jenkins/observability/CNPG); NAP adds ephemeral,
    scale-to-zero capacity for bursty CI agents. Pause/resume (Day2.scale.*) toggle NAP
    out-of-band via gcloud; a later Day1 apply reconciles it back on (the resume
    semantics), so that drift is expected and benign.

    NOTE: do not set this directly in CI — it is DRIVEN from the single config flag
    `nodeAutoProvisioning.enabled` in config/config.yaml. scripts/lib/config.sh,
    test/e2e.sh and the Day1 workflow all export TF_VAR_enable_node_autoprovisioning from
    that flag, so the cluster-level NAP toggle can never desync from the in-cluster
    ComputeClass wiring. The `true` default here only applies to a bare `terraform apply`
    with no TF_VAR set.
  EOT
  default     = true
}

variable "nap_max_cpu" {
  type        = number
  description = "NAP upper bound on total vCPUs across all auto-provisioned pools (a cost guardrail; the static pool is counted separately)."
  default     = 64
}

variable "nap_max_memory_gb" {
  type        = number
  description = "NAP upper bound on total memory (GB) across all auto-provisioned pools (cost guardrail)."
  default     = 256
}

variable "disk_size_gb" {
  type        = number
  description = "Boot disk size (GB) per node."
  default     = 50
}

variable "subnet_cidr" {
  type        = string
  description = "Primary IPv4 CIDR for the GKE subnet (node IPs)."
  default     = "10.10.0.0/20"
}

variable "pods_cidr" {
  type        = string
  description = "Secondary IPv4 CIDR for pod IPs (VPC-native cluster)."
  default     = "10.20.0.0/16"
}

variable "services_cidr" {
  type        = string
  description = "Secondary IPv4 CIDR for Service ClusterIPs (VPC-native cluster)."
  default     = "10.30.0.0/20"
}

variable "observability_llm_enabled" {
  type        = bool
  description = <<-EOT
    Create the keyless Vertex AI trust chain for the Grafana LLM app (AI
    assistant) used in observability.mode=oss: the grafana-llm GSA with
    roles/aiplatform.user plus the Workload Identity binding that lets the
    in-cluster LiteLLM gateway's KSA impersonate it. No static API key anywhere.

    NOTE: do not set this directly in CI — it is DRIVEN from the single config
    flag `observability.llm.enabled` in config/config.yaml. scripts/lib/config.sh,
    test/e2e.sh and the Day1 workflow all export TF_VAR_observability_llm_enabled
    from that flag, so the cloud IAM and the in-cluster wiring
    (scripts/08.8-grafana-llm.sh) can never desync — same single-source-of-truth
    pattern as enable_node_autoprovisioning above.
  EOT
  default     = false
}

variable "grafana_llm_gsa_account_id" {
  type        = string
  description = "account_id of the Grafana LLM GSA (the Workload Identity target of the LiteLLM pod). Must match observability.llm.gcp.googleServiceAccount in config/config.yaml."
  default     = "grafana-llm-gsa"
}

variable "grafana_llm_ksa_namespace" {
  type        = string
  description = "Namespace of the LiteLLM KSA bound to the Grafana LLM GSA (the observability namespace)."
  default     = "observability"
}

variable "grafana_llm_ksa_name" {
  type        = string
  description = "Name of the LiteLLM KSA bound to the Grafana LLM GSA. Must match observability.llm.gcp.kubernetesServiceAccount in config/config.yaml."
  default     = "grafana-llm-sa"
}

variable "admin_emails" {
  type        = list(string)
  description = "Google account emails granted roles/iap.httpsResourceAccessor, gating access through Identity-Aware Proxy to Jenkins and Headlamp. Also granted roles/container.clusterViewer for Headlamp's in-app per-user OIDC->GKE-API auth, which doesn't work today (see README.md \"Headlamp\") - kept for if/when upstream fixes that. Never commit real emails - set via TF_VAR_admin_emails."
  default     = []
}

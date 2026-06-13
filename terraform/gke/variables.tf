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
  description = "Machine type for cluster nodes. e2-standard-4 (4 vCPU/16GB) comfortably runs Jenkins + 18 PetClinic pods + the OTel collectors plus 1-2 concurrent build agent pods."
  default     = "e2-standard-4"
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

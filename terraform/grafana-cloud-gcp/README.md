# terraform/grafana-cloud-gcp

Read-only GCP service account for **Grafana Cloud → Observability → Cloud provider →
GCP**. That integration is a Grafana-Cloud-hosted scraper that pulls **GCP Cloud
Monitoring** metrics (GKE control plane, Compute, the L7 Gateway/LB, GCS, quotas, …)
into your stack — **no in-cluster collector**, complementary to our OTel pipeline.

## Why this is "human-run" + has a key (the one keyless exception)

Everything else in this repo authenticates keyless (GitHub→GCP WIF, the collector→
Azure/AWS via federated tokens). Grafana Cloud's GCP scraper is **not** a GCP workload,
so it can't use Workload Identity Federation — it needs a **service-account key (JSON)**
uploaded in the Grafana Cloud UI. This module IaC-manages the durable part (the SA +
read-only roles) but **deliberately does not create the key** (a long-lived key in
Terraform state would defeat the purpose). It's a one-time, project-level IAM grant —
run by hand with local state, like `terraform/bootstrap`. Optional / opt-in.

## Setup

```bash
cd terraform/grafana-cloud-gcp
terraform init
terraform apply -var project_id=<your-gke-project>      # e.g. woven-icon-499218-r9

# Mint a key for Grafana Cloud (the `key_command` output prints this):
gcloud iam service-accounts keys create grafana-cloud-gcp-key.json \
  --iam-account="$(terraform output -raw service_account_email)"
```

Then in **Grafana Cloud → Observability → Cloud provider → GCP**: add the project, paste
the key JSON, and select the GCP services to scrape. **Delete the local key file after
uploading**, and disable/rotate keys you no longer use (it's a long-lived credential).

For **GCP Logs** too, add `roles/logging.viewer` to `var.roles` and follow Grafana's
Pub/Sub export steps (out of scope here — metrics only by default).

## Teardown

`terraform destroy` removes the SA (and revokes any keys minted from it). Also remove
the integration in the Grafana Cloud UI.

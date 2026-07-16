#!/usr/bin/env bash
# Prints the "ACCESS URLs" block for the current cluster — the single source shared
# by Day1.cluster.01-gke and every Day2.redeploy.* workflow (and runnable locally).
#
# Engine-aware (Jenkins UI / Tekton Dashboard / GitHub Actions fork tabs / Argo UI),
# observability-mode-aware (the Grafana URL), and gateway-aware. Everything is derived
# from lib/config.sh (so the JENKINS2026_* overrides a workflow exports flow straight
# through — same engine/mode/domain the deploy scripts used), with two optional env knobs:
#   AU_ENABLE_GATEWAY  true|false  (default true — a running cluster has the Gateway; set
#                                   false only when a run provisioned with enable_gateway=false)
#   AU_DEVELOP_TRACK   true|false  (default false — show the lean develop microservices route)
#
# Why a script and not inline YAML: the block is ~90 lines of engine branching that used to
# live ONLY in Day1's "Access URLs" step, so a Day2.redeploy.* left the operator with no URL
# summary at all (and githubactions has no in-cluster UI, so its "where do my runs live" answer
# — each fork's Actions tab — is exactly the thing you need printed). One copy, no drift.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

dom="${J2026_GATEWAY_BASE_DOMAIN}"
engine="${J2026_CI_ENGINE}"
mode="${J2026_OBS_MODE}"
enable_gateway="${AU_ENABLE_GATEWAY:-true}"
develop_track="${AU_DEVELOP_TRACK:-false}"
obs_ns="${J2026_OBS_NAMESPACE:-observability}"

# Grafana URL depends on the observability mode (not the gateway/engine). oss = the
# in-cluster IAP host; grafana-cloud = the stack URL; managed-* = the workspace endpoint —
# both of the latter read from the in-cluster credentials Secret (robust in a redeploy, which
# has no Terraform step outputs to read a slug from).
grafana_note="${mode}"
case "${mode}" in
  oss)           grafana_url="https://grafana.${dom}"; grafana_note="IAP" ;;
  grafana-cloud) grafana_url="$(kubectl get secret "${J2026_GRAFANA_CLOUD_SECRET}" -n "${obs_ns}" -o jsonpath='{.data.GRAFANA_BASE_URL}' 2>/dev/null | base64 -d 2>/dev/null || true)"; grafana_note="Grafana Cloud sign-in" ;;
  managed-azure) grafana_url="$(kubectl get secret "${J2026_AZURE_MONITOR_SECRET}" -n "${obs_ns}" -o jsonpath='{.data.GRAFANA_BASE_URL}' 2>/dev/null | base64 -d 2>/dev/null || true)"; grafana_note="Azure Managed" ;;
  managed-aws)   grafana_url="$(kubectl get secret "${J2026_AWS_MANAGED_SECRET}" -n "${obs_ns}" -o jsonpath='{.data.GRAFANA_BASE_URL}' 2>/dev/null | base64 -d 2>/dev/null || true)"; grafana_note="Amazon Managed" ;;
  *)             grafana_url="" ;;
esac
grafana="${grafana_url:-(see the ${mode} backend / terraform outputs)}  (${grafana_note})"

# CI-engine-specific UI (mutually exclusive). githubactions has NO in-cluster UI: runs live in
# GitHub's Actions tab, ARC only supplies the in-cluster ephemeral Spot runners — so instead of
# an IAP URL it lists each microservices fork's Actions tab, read from the SAME services.yaml the
# seed renders from (06-githubactions-pipelines.sh), so the URLs are always accurate.
ci_open=""
if [[ "${engine}" == "tekton" ]]; then
  ci_iap="    Tekton Dashboard:      https://tekton.${dom}"
  ci_open=$'\n''    Tekton PaC webhook:    https://pac.'"${dom}"'  (GitHub -> Pipelines-as-Code, HMAC, no IAP)'
elif [[ "${engine}" == "githubactions" ]]; then
  ci_iap="    CI (GitHub Actions):   no in-cluster UI — pipelines run in each fork's Actions tab:"
  svc_file="${J2026_ROOT_DIR}/jenkins/pipelines/seed/services.yaml"
  if command -v yq >/dev/null 2>&1 && [[ -f "${svc_file}" ]]; then
    while IFS= read -r u; do
      [[ -z "${u}" || "${u}" == "null" ]] && continue
      ci_iap+=$'\n'"      ${u%.git}/actions"
    done < <(yq eval '.services[].repoUrl' "${svc_file}" 2>/dev/null | sort -u)
  fi
  ci_iap+=$'\n'"      (ARC ephemeral Spot runners execute these — GitHub hosts the UI; see docs/405)"
elif [[ "${engine}" == "argoworkflows" ]]; then
  ci_iap="    Argo Workflows UI:     https://argo.${dom}"
  ci_open=$'\n''    Argo Events webhook:   https://argo-events.'"${dom}"'  (GitHub -> Argo Events Sensor, HMAC, no IAP)'
else
  ci_iap="    Jenkins:               https://jenkins.${dom}"
fi

echo "════════════════════════════════════════════════════════════════════════"
echo "  ACCESS URLs   (ci_engine=${engine}, observability_mode=${mode})"
echo "════════════════════════════════════════════════════════════════════════"
if [[ "${enable_gateway}" == "true" ]]; then
  echo "  Behind Google IAP — sign in with an authorized Google account:"
  echo "    ArgoCD:                https://argocd.${dom}  (single sign-on: IAP + Dex authproxy; admin email = role:admin, else readonly)"
  echo "${ci_iap}"
  echo "    Headlamp:              https://headlamp.${dom}"
  echo "    pgAdmin:               https://pgadmin.${dom}"
  if [[ "${J2026_BACKSTAGE_ENABLED}" == "true" ]]; then
    echo "    Backstage:             https://backstage.${dom}  (developer portal; image bootstrap = Day2.publish.06 — docs/505)"
  fi
  [[ "${mode}" == "oss" ]] && echo "    Grafana (OSS):         https://grafana.${dom}"
  echo
  echo "  Open (no IAP):"
  echo "    Microservices:         https://microservices.${dom}${ci_open}"
  if [[ "${develop_track}" == "true" ]]; then
    echo "    Microservices develop: https://microservices-develop.${dom}"
  fi
  echo "    Faro RUM ingest:       https://faro.${dom}  (browser Faro beacon → otel-collector; not a UI — the Angular SPA posts here)"
  echo
  echo "  Observability:"
  echo "    Grafana:               ${grafana}"
  echo
  echo "  (IAP URLs need the one-time Day0.infra.01 Gateway + DNS + IAP OAuth client.)"
  echo
  echo "  ⚠️  NOTE on GKE Gateway Convergence:"
  echo "       The GKE Gateway compiles into a Google global external load balancer that then needs ~2-5 min to"
  echo "       (1) finish programming its forwarding rules + HTTPRoutes, and (2) mark each backend's NEG endpoints"
  echo "       HEALTHY via the LB health checks before it will route to them — and with backend TLS on, that"
  echo "       health check must converge to HTTPS first. IAP/OAuth on the admin UIs also settles in this window."
  echo "       So a browser hit right now can return 502, an SSL error, or 'upstream connect error ... reset"
  echo "       reason: local connection failure' — that is the LB with no healthy backend yet, not a broken run."
  echo "       Nothing to do: wait a few minutes and refresh. (See docs/504 § GKE NEG self-healing for the details.)"
else
  echo "  Gateway/IAP disabled for this run (AU_ENABLE_GATEWAY=false) — no public URLs."
  echo "  Reach services via 'kubectl port-forward' (see README 'Accessing the UI')."
  echo "    Grafana:               ${grafana}"
fi
echo "════════════════════════════════════════════════════════════════════════"

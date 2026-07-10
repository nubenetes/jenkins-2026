#!/usr/bin/env bash
# Grafana Graft chat (community vikshana-graft-app) - OPT-IN via
# observability.graft.enabled / JENKINS2026_OBS_GRAFT_ENABLED, default false,
# oss mode ONLY, and REQUIRES observability.llm.enabled (config.sh enforces it).
#
# The plugin itself is installed by a FAIL-OPEN init container layered onto the
# Grafana pod by the observability-oss app-of-apps (values-oss-graft.yaml) when
# 03-observability.sh passes graftEnabled=true. This script provides the
# script-managed COMPANION that the "always the latest stable release" +
# auto-update requirement needs:
#
#   - a CronJob (+ its RBAC + a small state ConfigMap) that polls the GitHub
#     releases API on observability.graft.autoUpdateSchedule and, when a newer
#     release appears, rolls the Grafana Deployment so its init container
#     re-pulls the latest release. Same companion-object pattern as
#     08.8-grafana-llm.sh's LiteLLM stack.
#
# grafana-cloud / managed-* -> NO-OP: Graft is oss-only (it rides the in-cluster
# grafana-llm-app + Grafana). When INACTIVE: symmetric retire - removes the
# CronJob + RBAC + state left by a previous enabled run (the init container /
# plugin self-heal away when 03 re-renders the app-of-apps without the overlay).
# Idempotent. Non-fatal: an optional feature must never wedge a provision.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

# Fixed names (the Grafana Deployment is the kube-prometheus-stack fullname,
# release 'oss'; the CronJob lives in Grafana's namespace so it can roll it).
GRAFANA_DEPLOYMENT="oss-kube-prometheus-stack-grafana"
GRAFT_SA="graft-updater"
GRAFT_ROLE="graft-updater"
GRAFT_CRONJOB="graft-autoupdate"
GRAFT_STATE_CM="graft-autoupdate-state"
NS="${J2026_GRAFANA_OSS_NAMESPACE}"

retire_graft_companions() {
  if kubectl get namespace "${NS}" >/dev/null 2>&1; then
    kubectl delete cronjob "${GRAFT_CRONJOB}" -n "${NS}" --ignore-not-found
    kubectl delete rolebinding "${GRAFT_ROLE}" -n "${NS}" --ignore-not-found
    kubectl delete role "${GRAFT_ROLE}" -n "${NS}" --ignore-not-found
    kubectl delete serviceaccount "${GRAFT_SA}" -n "${NS}" --ignore-not-found
    kubectl delete configmap "${GRAFT_STATE_CM}" -n "${NS}" --ignore-not-found
  fi
}

# --- non-oss modes: retire-and-exit -------------------------------------------
if [[ "${J2026_OBS_MODE}" != "oss" ]]; then
  retire_graft_companions
  if [[ "${J2026_OBS_GRAFT_ENABLED}" == "true" ]]; then
    log_warn "observability.graft.enabled=true has NO effect in ${J2026_OBS_MODE}: Graft is oss-only (it rides the in-cluster grafana-llm-app + Grafana). See docs/301 § Grafana Graft chat."
  else
    log_info "Grafana Graft chat: nothing to do in ${J2026_OBS_MODE} (oss-only feature)."
  fi
  exit 0
fi

# --- oss, flag off: retire ----------------------------------------------------
if [[ "${J2026_OBS_GRAFT_ENABLED}" != "true" ]]; then
  log_step "Grafana Graft chat is off (observability.graft.enabled=false) - retiring any leftovers"
  retire_graft_companions
  log_info "Grafana Graft chat is off - nothing more to do."
  exit 0
fi

# ==============================================================================
# ENABLE (oss): auto-update CronJob + RBAC + state ConfigMap
# ==============================================================================
log_step "Grafana Graft chat auto-update (CronJob polling ${J2026_OBS_GRAFT_GITHUB_REPO}, schedule '${J2026_OBS_GRAFT_AUTOUPDATE_SCHEDULE}')"

kubectl apply -f - <<EOT
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${GRAFT_SA}
  namespace: ${NS}
  labels:
    app.kubernetes.io/name: graft-autoupdate
    app.kubernetes.io/part-of: jenkins-2026
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${GRAFT_ROLE}
  namespace: ${NS}
  labels:
    app.kubernetes.io/part-of: jenkins-2026
rules:
  # Roll the Grafana Deployment so its init container re-pulls the latest Graft.
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "patch"]
  # Track the last-applied release tag so we only roll on a genuine change.
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "create", "patch", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${GRAFT_ROLE}
  namespace: ${NS}
  labels:
    app.kubernetes.io/part-of: jenkins-2026
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ${GRAFT_ROLE}
subjects:
  - kind: ServiceAccount
    name: ${GRAFT_SA}
    namespace: ${NS}
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ${GRAFT_CRONJOB}
  namespace: ${NS}
  labels:
    app.kubernetes.io/name: graft-autoupdate
    app.kubernetes.io/part-of: jenkins-2026
spec:
  schedule: "${J2026_OBS_GRAFT_AUTOUPDATE_SCHEDULE}"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      backoffLimit: 1
      activeDeadlineSeconds: 300
      template:
        metadata:
          labels:
            app.kubernetes.io/name: graft-autoupdate
        spec:
          serviceAccountName: ${GRAFT_SA}
          restartPolicy: Never
          containers:
            - name: graft-autoupdate
              # alpine/k8s bundles kubectl + curl + jq (also used by the CI agents).
              image: alpine/k8s:1.31.3
              command: ["/bin/sh", "-c"]
              args:
                - |
                  set -u
                  REPO="${J2026_OBS_GRAFT_GITHUB_REPO}"
                  DEPLOY="${GRAFANA_DEPLOYMENT}"
                  CM="${GRAFT_STATE_CM}"
                  NS="\$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)"
                  LATEST="\$(curl -fsSL --max-time 30 "https://api.github.com/repos/\${REPO}/releases/latest" 2>/dev/null | jq -r '.tag_name // empty')"
                  if [ -z "\${LATEST}" ]; then echo "could not resolve latest release (GitHub unreachable/rate-limited) — skipping this cycle"; exit 0; fi
                  SEEN="\$(kubectl -n "\${NS}" get configmap "\${CM}" -o jsonpath='{.data.tag}' 2>/dev/null || true)"
                  if [ "\${LATEST}" = "\${SEEN}" ]; then echo "Graft already at \${LATEST} — no update"; exit 0; fi
                  echo "New Graft release \${LATEST} (was \${SEEN:-none}) — rolling \${DEPLOY} so its init container re-pulls it"
                  kubectl -n "\${NS}" rollout restart deployment/"\${DEPLOY}"
                  kubectl -n "\${NS}" patch configmap "\${CM}" --type merge -p "{\"data\":{\"tag\":\"\${LATEST}\"}}" 2>/dev/null \
                    || kubectl -n "\${NS}" create configmap "\${CM}" --from-literal=tag="\${LATEST}"
                  echo "recorded \${LATEST}"
              resources:
                requests: {cpu: 10m, memory: 64Mi}
                limits: {cpu: 200m, memory: 128Mi}
              securityContext:
                allowPrivilegeEscalation: false
EOT

# Seed the state ConfigMap if absent so the first CronJob run only rolls Grafana
# when there is a genuinely newer release than what the init container fetched at
# deploy time (best-effort; a missing tag just triggers one harmless roll).
kubectl get configmap "${GRAFT_STATE_CM}" -n "${NS}" >/dev/null 2>&1 \
  || kubectl create configmap "${GRAFT_STATE_CM}" -n "${NS}" --from-literal=tag="" 2>/dev/null || true

log_info "Grafana Graft chat wired: init container installs the latest ${J2026_OBS_GRAFT_PLUGIN_ID} release; CronJob '${GRAFT_CRONJOB}' auto-updates on new releases. Grafana stays resilient if the plugin download fails (fail-open init)."

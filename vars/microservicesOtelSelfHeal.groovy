/**
 * microservicesOtelSelfHeal(serviceName: '<svc>', namespace: '<ns>')
 *
 * The body of the Declarative 'OTel Self-Heal' stage: heals the OTel
 * auto-instrumentation injection race after the GitOps deploy.
 *
 * The operator's pod-mutation webhook (mpod.kb.io) uses failurePolicy: Ignore,
 * so a pod admitted before the Instrumentation CR was ready starts WITHOUT the
 * Java agent and emits no metrics/traces (Grafana dashboards look empty). After
 * the ArgoCD sync, the new pod may have this problem — detect it (JAVA_TOOL_OPTIONS
 * must carry -javaagent) and fix it with a rollout restart. Split out of
 * vars/microservicesDeploy.groovy so the check — and any restart it triggers —
 * is visible as its own stage in the build UI. The same self-heal lives in Tekton's
 * gitops-deploy task (docs/404) and the Argo Workflows template (docs/406). It is
 * NOT yet ported to the GitHub Actions rendered workflow (docs/405 § The pipeline,
 * rendered into each fork): its RBAC is already granted to the ARC runner, only the
 * step is missing — so a GHA deploy that loses the webhook race leaves the pod
 * uninstrumented with nothing to heal it.
 *
 * The check inspects ONLY the app container (named after the service in the chart).
 * Scanning every container in the pod is exactly what let a real bug through: with
 * the service mesh on, CSM injects istio-proxy AHEAD of the app and the OTel Operator
 * instruments the FIRST container unless instrumentation.opentelemetry.io/container-names
 * pins it — so the SIDECAR carried the -javaagent, this stage happily reported "✓",
 * and the app ran uninstrumented with every OTel-fed Grafana panel on "No data".
 * See docs/506 § App mesh-readiness.
 *
 * Outcomes (exit code → build result, same convention as vars/microservicesK6Smoke):
 *   0   agent on the app container (possibly after a self-healing restart), or no pod yet
 *   99  agent present but on the WRONG container → UNSTABLE (a restart cannot fix it)
 *   *   anything else → the stage fails
 */
def call(Map cfg) {
  container('helm') {
    def rc = sh(returnStatus: true, script: """
      set -eux
      NAMESPACE="${cfg.namespace}"
      DEPLOY="${cfg.serviceName}"

      # Wait for at least one Ready pod before checking injection
      kubectl -n "\${NAMESPACE}" rollout status deploy/"\${DEPLOY}" --timeout=120s || true

      # Pods carry app.kubernetes.io/name, not plain app — use that label.
      POD=\$(kubectl -n "\${NAMESPACE}" get pods \
            -l "app.kubernetes.io/name=\${DEPLOY}" \
            --field-selector=status.phase=Running -o name 2>/dev/null | head -1)
      if [[ -z "\${POD}" ]]; then
        echo "No running pod for \${DEPLOY} — skipping OTel injection check"
        exit 0
      fi

      # ONLY the app container counts — it is named after the service in the chart.
      app_jto() {
        kubectl -n "\${NAMESPACE}" get "\$1" \
          -o jsonpath="{.spec.containers[?(@.name=='\${DEPLOY}')].env[?(@.name=='JAVA_TOOL_OPTIONS')].value}" \
          2>/dev/null || true
      }
      # Every container as name=value — used ONLY to tell a mis-target from the race.
      all_jto() {
        kubectl -n "\${NAMESPACE}" get "\$1" \
          -o jsonpath='{range .spec.containers[*]}{.name}{"="}{.env[?(@.name=="JAVA_TOOL_OPTIONS")].value}{" "}{end}' \
          2>/dev/null || true
      }

      if app_jto "\${POD}" | grep -q -- '-javaagent'; then
        echo "OTel agent injected in the \${DEPLOY} APP container ✓"
        exit 0
      fi

      # The agent exists somewhere in the pod, just not on the app → MIS-TARGET, not the
      # webhook race. A restart cannot fix it: the operator would pick the same wrong
      # (first) container again. Say so precisely instead of looping or passing silently.
      if all_jto "\${POD}" | grep -q -- '-javaagent'; then
        echo "ERROR: the OTel agent landed on the WRONG container — \${DEPLOY} is NOT instrumented,"
        echo "       so it emits no traces/metrics and its Grafana panels will read 'No data'."
        echo "       per-container JAVA_TOOL_OPTIONS: \$(all_jto "\${POD}")"
        echo "       A rollout restart will NOT fix this. The OTel Operator instruments the FIRST"
        echo "       container, and a service-mesh sidecar (istio-proxy) is injected ahead of the app."
        echo "       FIX: set instrumentation.opentelemetry.io/container-names=\${DEPLOY} on the pod"
        echo "       template in the gitops-config chart. See docs/506 § App mesh-readiness."
        exit 99
      fi

      echo "OTel agent NOT injected in \${DEPLOY} (webhook race) — rolling restart to trigger injection"
      kubectl -n "\${NAMESPACE}" rollout restart deploy/"\${DEPLOY}"
      kubectl -n "\${NAMESPACE}" rollout status deploy/"\${DEPLOY}" --timeout=120s
      POD2=\$(kubectl -n "\${NAMESPACE}" get pods \
             -l "app.kubernetes.io/name=\${DEPLOY}" \
             --field-selector=status.phase=Running -o name 2>/dev/null | head -1)
      if [[ -n "\${POD2}" ]] && app_jto "\${POD2}" | grep -q -- '-javaagent'; then
        echo "OTel agent injected in the \${DEPLOY} APP container after restart ✓"
        exit 0
      fi
      echo "WARNING: OTel agent still not injected after restart — check the OTel Operator webhook"
      exit 0
    """)

    if (rc == 99) {
      // Mis-targeted agent: the deploy itself is fine, but the service is emitting nothing.
      // Surface it as UNSTABLE (the k6-smoke convention) rather than passing green — a
      // silent pass is precisely how this bug reached the dashboards unnoticed.
      unstable("OTel agent injected into the wrong container for ${cfg.serviceName} — the app is NOT instrumented (see the stage log)")
    } else if (rc != 0) {
      error("OTel self-heal check failed for ${cfg.serviceName} (exit ${rc})")
    }
  }
}

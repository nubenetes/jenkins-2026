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
 * is visible as its own stage in the build UI. The same self-heal exists in the
 * other engines' gitops-deploy task/step (docs/404 · 405 · 406).
 */
def call(Map cfg) {
  container('helm') {
    sh """
      set -eux
      NAMESPACE="${cfg.namespace}"
      DEPLOY="${cfg.serviceName}"

      # Wait for at least one Ready pod before checking injection
      kubectl -n "\${NAMESPACE}" rollout status deploy/"\${DEPLOY}" --timeout=120s || true

      # Get JAVA_TOOL_OPTIONS from a running pod.
      # Pods carry app.kubernetes.io/name, not plain app — use that label.
      POD=\$(kubectl -n "\${NAMESPACE}" get pods \
            -l "app.kubernetes.io/name=\${DEPLOY}" \
            --field-selector=status.phase=Running -o name 2>/dev/null | head -1)
      if [[ -z "\${POD}" ]]; then
        echo "No running pod for \${DEPLOY} — skipping OTel injection check"
      else
        JTO=\$(kubectl -n "\${NAMESPACE}" get "\${POD}" \
               -o jsonpath='{range .spec.containers[*]}{.env[?(@.name=="JAVA_TOOL_OPTIONS")].value}{end}' \
               2>/dev/null || true)
        if echo "\${JTO}" | grep -q -- '-javaagent'; then
          echo "OTel agent already injected in \${DEPLOY} ✓"
        else
          echo "OTel agent NOT injected in \${DEPLOY} (race condition) — rolling restart to trigger injection"
          kubectl -n "\${NAMESPACE}" rollout restart deploy/"\${DEPLOY}"
          kubectl -n "\${NAMESPACE}" rollout status deploy/"\${DEPLOY}" --timeout=120s
          POD2=\$(kubectl -n "\${NAMESPACE}" get pods \
                 -l "app.kubernetes.io/name=\${DEPLOY}" \
                 --field-selector=status.phase=Running -o name 2>/dev/null | head -1)
          JTO2=\$(kubectl -n "\${NAMESPACE}" get "\${POD2}" \
                 -o jsonpath='{range .spec.containers[*]}{.env[?(@.name=="JAVA_TOOL_OPTIONS")].value}{end}' \
                 2>/dev/null || true)
          if echo "\${JTO2}" | grep -q -- '-javaagent'; then
            echo "OTel agent injected after restart ✓"
          else
            echo "WARNING: OTel agent still not injected after restart — check OTel Operator webhook"
          fi
        fi
      fi
    """
  }
}

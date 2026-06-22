/**
 * microservicesDeploy(serviceName: '<svc>', envName: 'stable'|'develop',
 *                  namespace: '<ns>', platform: 'gke',
 *                  tag: '<image-tag>')
 *
 * GitOps Version: Updates the image tag in helm/microservices/values-<env>.yaml
 * in the INFRA repo (this one) and pushes to Git. ArgoCD handles the deploy.
 */
def call(Map cfg) {
  // Only 'stable' and the optional 'develop' tier are deployable. Reject anything
  // else fast (clear error) instead of pushing an image-tag bump to a
  // non-existent gitops branch / ArgoCD app and failing later with a confusing
  // "application not found". The 'develop' tier is gated upstream by the seed job,
  // which only generates develop jobs when it is enabled (config
  // microservices.developTrackEnabled / JENKINS2026_DEVELOP_TRACK_ENABLED).
  if (!(cfg.envName in ['stable', 'develop'])) {
    error("microservicesDeploy: unsupported envName '${cfg.envName}' (expected 'stable' or 'develop').")
  }

  def infraRepoUrl = env.JENKINS2026_GITOPS_REPO_URL ?: "https://github.com/nubenetes/jenkins-2026-gitops-config.git"
  def valuesFile = "helm/microservices/values-${cfg.envName}.yaml"

  // Use the gitops branch that corresponds to the environment.
  def infraBranch = cfg.envName == 'stable' ? 'main' : 'develop'

  // Use 'jenkins-2026-gitops' (not 'jenkins-2026-infra') to avoid colliding
  // with the infra checkout dir that Checkout Infra configs clones into.
  // Cleanup runs inside container('git') so root can delete root-owned files
  // from previous builds; deleteDir() outside containers fails with EPERM.
  dir('jenkins-2026-gitops') {
    stage('GitOps Update') {
      container('git') {
        withCredentials([usernamePassword(credentialsId: 'microservices-git',
                                         passwordVariable: 'GIT_TOKEN',
                                         usernameVariable: 'GIT_USER')]) {
          sh """
            set -eux
            git config --global --add safe.directory '*' || true
            git config --global user.email "jenkins@nubenetes.com"
            git config --global user.name "Jenkins CI"

            # Clean any previous clone inside the container that created it (EPERM-safe)
            find . -mindepth 1 -delete 2>/dev/null || true

            # Construct the remote URL with credentials
            REPO_URL="${infraRepoUrl}"
            REPO_CLEAN=\$(echo "\${REPO_URL}" | sed 's|https://||')
            AUTH_REPO_URL="https://\${GIT_USER:-git}:\${GIT_TOKEN:-}@\${REPO_CLEAN}"

            git clone --depth 1 --branch ${infraBranch} "\${AUTH_REPO_URL}" .
          """
        }
      }
      
      container('helm') {
        sh """
          # Update the tag using yq (available in alpine/k8s)
          yq eval -i '.services.${cfg.serviceName}.image.tag = "${cfg.tag}"' ${valuesFile}
        """
      }

      container('git') {
        withCredentials([usernamePassword(credentialsId: 'microservices-git', 
                                         passwordVariable: 'GIT_TOKEN', 
                                         usernameVariable: 'GIT_USER')]) {
          sh """
            set -eux
            git config --global --add safe.directory '*'
            git add ${valuesFile}
            git commit -m "chore(ops): update ${cfg.serviceName} image tag to ${cfg.tag} [${cfg.envName}]" || echo "No changes to commit"
            
            # Push back to the infra branch
            git push origin ${infraBranch}
          """
        }
      }

      container('helm') {
        sh """
          set -eux
          # Download argocd CLI to /tmp — helm container runs as UID 1001
          # (non-root) so /usr/local/bin is not writable.
          ARGOCD=/tmp/argocd-cli
          if [ ! -x "\${ARGOCD}" ]; then
            curl -sSL -o "\${ARGOCD}" https://github.com/argoproj/argo-cd/releases/download/\${ARGOCD_VERSION}/argocd-linux-amd64
            chmod +x "\${ARGOCD}"
          fi

          # Trigger and wait for Sync
          # Using --grpc-web because we are connecting to the internal service which might not have full HTTP/2 support in all environments
          # Using --insecure because we are connecting to the internal service via .local DNS
          local_server="\${ARGOCD_SERVER:-argocd-server.argocd.svc.cluster.local}"
          local_flags="--grpc-web --insecure"
          if [[ "\${local_server}" != *":"* || "\${local_server}" == *":80" ]]; then
            if [[ "\${local_server}" != *":"* ]]; then
              local_server="\${local_server}:80"
            fi
            local_flags="\${local_flags} --plaintext"
          fi

          \${ARGOCD} app sync "microservices-${cfg.envName}" \
            --server "\${local_server}" \
            --auth-token "\${ARGOCD_AUTH_TOKEN:-}" \
            \${local_flags}

          \${ARGOCD} app wait "microservices-${cfg.envName}" \
            --sync --timeout 300 \
            --server "\${local_server}" \
            --auth-token "\${ARGOCD_AUTH_TOKEN:-}" \
            \${local_flags}
        """
      }

      // Self-heal the OTel auto-instrumentation injection race.
      // The operator's pod-mutation webhook (mpod.kb.io) uses failurePolicy:Ignore,
      // so a pod admitted before the Instrumentation CR was ready starts WITHOUT
      // the Java agent and emits no metrics/traces (Grafana dashboards look empty).
      // After ArgoCD sync, the new pod may have this problem — detect and fix it.
      container('helm') {
        sh """
          set -eux
          NAMESPACE="${cfg.targetNamespace}"
          DEPLOY="${cfg.serviceName}"

          # Wait for at least one Ready pod before checking injection
          kubectl -n "\${NAMESPACE}" rollout status deploy/"\${DEPLOY}" --timeout=120s || true

          # Get JAVA_TOOL_OPTIONS from a running pod
          POD=\$(kubectl -n "\${NAMESPACE}" get pods -l app="\${DEPLOY}" \
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
              # Verify after restart
              POD2=\$(kubectl -n "\${NAMESPACE}" get pods -l app="\${DEPLOY}" \
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
  }
}

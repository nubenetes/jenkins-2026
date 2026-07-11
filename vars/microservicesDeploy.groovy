/**
 * microservicesDeploy(serviceName: '<svc>', envName: 'stable'|'develop',
 *                  tag: '<image-tag>')
 *
 * The body of the Declarative 'GitOps Update' stage — the cross-engine deploy
 * phase (docs/502): updates the image tag in helm/microservices/values-<env>.yaml
 * in the jenkins-2026-gitops-config repo (cloned separately, not this one),
 * pushes to Git, then triggers + waits for the ArgoCD sync. ArgoCD performs the
 * actual Kubernetes rollout. The follow-up OTel injection check is its own stage
 * (vars/microservicesOtelSelfHeal.groovy).
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
        # Download argocd CLI to /tmp — helm container runs as UID 1000
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

        synced=0
        for attempt in 1 2 3 4 5 6; do
          if \${ARGOCD} app sync "microservices-${cfg.envName}" --server "\${local_server}" --auth-token "\${ARGOCD_AUTH_TOKEN:-}" \${local_flags}; then
            synced=1; break
          fi
          echo "app sync attempt \${attempt} failed (likely a concurrent auto-sync); retrying in 10s..."
          sleep 10
        done
        [ "\${synced}" = 1 ] || echo "Proceeding without an explicit sync — verifying convergence via 'app wait' (auto-sync handles the deploy)."

        # app wait uses --timeout 900 (raised from 300): it waits on the WHOLE ArgoCD Application, so the
        # gateway's ~600s startupProbe cold-start gates every service's run in the batch - don't lower (see CHANGELOG).
        \${ARGOCD} app wait "microservices-${cfg.envName}" \
          --sync --health --timeout 900 \
          --server "\${local_server}" \
          --auth-token "\${ARGOCD_AUTH_TOKEN:-}" \
          \${local_flags}
      """
    }
  }
}

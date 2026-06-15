/**
 * microservicesDeploy(serviceName: '<svc>', envName: 'stable'|'develop',
 *                  namespace: '<ns>', platform: 'gke'|'eks'|'aks'|'openshift',
 *                  tag: '<image-tag>')
 *
 * GitOps Version: Updates the image tag in helm/microservices/values-<env>.yaml
 * in the INFRA repo (this one) and pushes to Git. ArgoCD handles the deploy.
 */
def call(Map cfg) {
  def infraRepoUrl = env.JENKINS2026_REPO_URL ?: "https://github.com/nubenetes/jenkins-2026.git"
  def valuesFile = "helm/microservices/values-${cfg.envName}.yaml"
  
  // Use the branch that corresponds to the environment
  def infraBranch = cfg.envName == 'stable' ? 'main' : 'develop'

  dir('jenkins-2026-infra') {
    stage('GitOps Update') {
      container('git') {
        withCredentials([usernamePassword(credentialsId: 'microservices-git', 
                                         passwordVariable: 'GIT_TOKEN', 
                                         usernameVariable: 'GIT_USER')]) {
          sh """
            set -eux
            git config --global user.email "jenkins@nubenetes.com"
            git config --global user.name "Jenkins CI"
            
            # Construct the remote URL with credentials
            REPO_URL="${infraRepoUrl}"
            REPO_CLEAN=\$(echo "\${REPO_URL}" | sed 's|https://||')
            AUTH_REPO_URL="https://\${GIT_USER:-git}:\${GIT_TOKEN}@\${REPO_CLEAN}"
            
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
          # Install argocd CLI if not present
          if ! command -v argocd >/dev/null 2>&1; then
            curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/\${ARGOCD_VERSION}/argocd-linux-amd64
            chmod +x /usr/local/bin/argocd
          fi

          # Trigger and wait for Sync
          # Using --grpc-web because we are connecting to the internal service which might not have full HTTP/2 support in all environments
          # Using --insecure because we are connecting to the internal service via .local DNS
          argocd app sync "microservices-${cfg.envName}" \
            --server "\${ARGOCD_SERVER}" \
            --auth-token "\${ARGOCD_AUTH_TOKEN}" \
            --grpc-web --insecure

          argocd app wait "microservices-${cfg.envName}" \
            --sync --health --timeout 300 \
            --server "\${ARGOCD_SERVER}" \
            --auth-token "\${ARGOCD_AUTH_TOKEN}" \
            --grpc-web --insecure
        """
      }
    }
  }
}

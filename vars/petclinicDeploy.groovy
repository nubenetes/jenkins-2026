/**
 * petclinicDeploy(serviceName: '<svc>', envName: 'stable'|'develop',
 *                  namespace: '<ns>', platform: 'gke'|'eks'|'aks'|'openshift',
 *                  tag: '<image-tag>')
 *
 * GitOps Version: Updates the image tag in helm/petclinic/values-<env>.yaml
 * in the INFRA repo (this one) and pushes to Git. ArgoCD handles the deploy.
 */
def call(Map cfg) {
  def infraRepoUrl = env.JENKINS2026_REPO_URL ?: "https://github.com/nubenetes/jenkins-2026.git"
  def valuesFile = "helm/petclinic/values-${cfg.envName}.yaml"
  
  // Use the branch that corresponds to the environment
  def infraBranch = cfg.envName == 'stable' ? 'main' : 'develop'

  dir('jenkins-2026-infra') {
    stage('GitOps Update') {
      container('git') {
        withCredentials([usernamePassword(credentialsId: 'petclinic-git', 
                                         passwordVariable: 'GIT_TOKEN', 
                                         usernameVariable: 'GIT_USER')]) {
          sh """
            set -eux
            git config --global user.email "jenkins@nubenetes.com"
            git config --global user.name "Jenkins CI"
            
            # Construct the remote URL with credentials
            REPO_URL="${infraRepoUrl}"
            REPO_CLEAN=\$(echo "\${REPO_URL}" | sed 's|https://||')
            AUTH_REPO_URL="https://\${GIT_USER}:\${GIT_TOKEN}@\${REPO_CLEAN}"
            
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
        withCredentials([usernamePassword(credentialsId: 'petclinic-git', 
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
    }
  }
}

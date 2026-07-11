/**
 * microservicesTrivyIacScan(envName: 'stable'|'develop')
 *
 * Trivy IaC/misconfiguration scan (trivy config) of (1) the checked-out app
 * source and (2) the microservices Helm chart in the gitops-config repo —
 * cloned here from the branch matching the tier (stable=main, develop=develop).
 *
 * Runs in the 'git' + 'trivy' containers of the pod template declared inline
 * in vars/MicroservicesPipeline.groovy; called from the parallel 'Static
 * Analysis' stage. The clone lands at the workspace ROOT (gitops-config-src/),
 * disjoint from the semgrep/codeql outputs under microservices-src/, so the
 * three parallel branches never contend. Non-blocking (--exit-code 0): findings
 * report, they don't gate (docs/601).
 */
def call(Map cfg) {
  container('git') {
    // Same JENKINS-30600 fix as Checkout Infra configs: use sh
    // so container() is honoured. Credentials embedded in the URL.
    withCredentials([usernamePassword(credentialsId: 'microservices-git',
                                     passwordVariable: 'GIT_TOKEN',
                                     usernameVariable: 'GIT_USER')]) {
      sh """
          git config --global --add safe.directory '*' || true
          rm -rf gitops-config-src
          REPO_URL="${env.JENKINS2026_GITOPS_REPO_URL ?: 'https://github.com/nubenetes/jenkins-2026-gitops-config.git'}"
          REPO_CLEAN=\$(echo "\${REPO_URL}" | sed 's|https://||')
          git clone --depth 1 \
              --branch ${cfg.envName == 'stable' ? 'main' : 'develop'} \
              "https://\${GIT_USER:-git}:\${GIT_TOKEN:-}@\${REPO_CLEAN}" \
              gitops-config-src
      """
    }
  }
  container('trivy') {
    dir('microservices-src') {
      sh """
          trivy config --config ${env.WORKSPACE}/jenkins-2026-infra/trivy.yaml --exit-code 0 .
      """
    }
    sh """
        trivy config --config ${env.WORKSPACE}/jenkins-2026-infra/trivy.yaml --exit-code 0 ${env.WORKSPACE}/gitops-config-src/helm/microservices
    """
  }
}

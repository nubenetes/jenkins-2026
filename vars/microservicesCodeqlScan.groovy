/**
 * microservicesCodeqlScan(repoUrl: cfg.gitRepoUrl, repoBranch: cfg.gitBranch)
 *
 * CodeQL deep-SAST scan of the checked-out app source (microservices-src/):
 * builds a local JavaScript/TypeScript CodeQL database (config from the infra
 * checkout's .github/codeql/codeql-config.yml), analyzes it, then the shared
 * SARIF upload to GitHub Code Scanning (microservicesSarifUpload).
 * repoUrl/repoBranch identify the scanned APP's own repo, not the infra
 * self-repo (see microservicesSarifUpload's header).
 *
 * Runs in the 'codeql' container of the pod template declared inline in
 * vars/MicroservicesPipeline.groovy; called from the parallel 'Static Analysis'
 * stage (this is the long pole of the three scanners — the reason the stage
 * fans out). Non-blocking by design (docs/601).
 */
def call(Map cfg) {
  container('codeql') {
    dir('microservices-src') {
      sh """
          git config --global --add safe.directory '*' || true
          echo "Upgrading Node.js inside CodeQL container to v20..."
          export DEBIAN_FRONTEND=noninteractive
          (apt-get update && apt-get install -y curl tar xz-utils) || true
          (curl -sL https://nodejs.org/dist/v20.11.1/node-v20.11.1-linux-x64.tar.xz | tar -xJ -C /usr/local --strip-components=1) || true
          node --version || true
          codeql database create codeql-db --language=javascript --source-root=. --threads=0 --ram=3500 --codescanning-config=${env.WORKSPACE}/jenkins-2026-infra/.github/codeql/codeql-config.yml
          codeql database analyze codeql-db --format=sarif-latest --output=codeql-results.sarif --threads=0 --ram=3500 || true
      """
      archiveArtifacts artifacts: 'codeql-results.sarif', allowEmptyArchive: true
    }
  }
  microservicesSarifUpload(
    sarifFile: 'codeql-results.sarif',
    toolName: 'CodeQL',
    uiDetail: 'data flow paths',
    repoUrl: cfg.repoUrl,
    repoBranch: cfg.repoBranch,
    blurb: [
      "CodeQL is GitHub's advanced semantic code analysis engine. By treating",
      'code as data, it executes queries to detect security vulnerabilities,',
      'data flow anomalies, and structural issues in your application stack.',
    ]
  )
}

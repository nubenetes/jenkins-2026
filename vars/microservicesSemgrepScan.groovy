/**
 * microservicesSemgrepScan(repoUrl: cfg.gitRepoUrl, repoBranch: cfg.gitBranch)
 *
 * Semgrep SAST scan of the checked-out app source (microservices-src/) using
 * the public security packs (p/security-audit, p/owasp-top-ten) plus this
 * repo's custom rules (.semgrep/semgrep.yml from the infra checkout), then the
 * shared SARIF upload to GitHub Code Scanning (microservicesSarifUpload).
 * repoUrl/repoBranch identify the scanned APP's own repo, not the infra
 * self-repo (see microservicesSarifUpload's header).
 *
 * Runs in the 'semgrep' container of the pod template declared inline in
 * vars/MicroservicesPipeline.groovy; called from the parallel 'Static Analysis'
 * stage. Non-blocking by design (docs/601): findings never fail the build here —
 * they surface via warnings-ng (post: recordIssues) and GitHub Code Scanning.
 */
def call(Map cfg) {
  container('semgrep') {
    dir('microservices-src') {
      sh """
          git config --global --add safe.directory '*' || true
          semgrep scan --config=p/security-audit --config=p/owasp-top-ten --config=${env.WORKSPACE}/jenkins-2026-infra/.semgrep/semgrep.yml --sarif --sarif-output=semgrep-results.sarif . || true
      """
      archiveArtifacts artifacts: 'semgrep-results.sarif', allowEmptyArchive: true
    }
  }
  microservicesSarifUpload(
    sarifFile: 'semgrep-results.sarif',
    toolName: 'Semgrep',
    uiDetail: 'code mappings',
    repoUrl: cfg.repoUrl,
    repoBranch: cfg.repoBranch,
    blurb: [
      'Semgrep is a fast, open-source static analysis tool for finding bugs,',
      'detecting vulnerabilities, and enforcing code standards during development.',
      'It uses syntax-aware pattern matching without needing a build step.',
    ]
  )
}

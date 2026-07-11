/**
 * microservicesSarifUpload(sarifFile: '<tool>-results.sarif', toolName: 'Semgrep',
 *                          blurb: ['what-is line 1', ...], uiDetail: 'code mappings')
 *
 * Shared SARIF -> GitHub Code Scanning upload used by the Semgrep and CodeQL
 * scan steps — one implementation instead of the two former copy-pasted 45-line
 * sh blobs in vars/MicroservicesPipeline.groovy.
 *
 * Runs in container('helm') — alpine/k8s has curl, git, gzip, and base64
 * pre-installed so no package install is needed; container('git') (alpine/git +
 * runAsUser:1000) cannot install packages (apk requires root) and lacks curl.
 * Payload is gzip+base64 per the code-scanning/sarifs API contract; HTTP 202 =
 * accepted. A non-202 (e.g. a fork without Advanced Security) warns but never
 * fails the build — scans are non-blocking reporters (docs/601).
 */
def call(Map cfg) {
  // Tool-specific log banner, prebuilt here so the sh blob stays generic.
  def prefix = cfg.toolName.toLowerCase()
  def banner = (cfg.blurb ?: []).collect { line ->
    "                                     echo \"${line}\""
  }.join('\n')

  container('helm') {
    dir('microservices-src') {
      withCredentials([usernamePassword(credentialsId: 'microservices-git',
                                       passwordVariable: 'GIT_TOKEN',
                                       usernameVariable: 'GIT_USER')]) {
        sh """
            git config --global --add safe.directory '*' || true
            if [ -f ${cfg.sarifFile} ]; then
                echo "Preparing ${cfg.toolName} SARIF report payload..."
                gzip -c ${cfg.sarifFile} | base64 -w0 > ${prefix}-sarif.b64
                COMMIT_SHA=\$(git -C ${env.WORKSPACE}/jenkins-2026-infra rev-parse HEAD | tr -d '\\n')
                REF="refs/heads/${env.JENKINS2026_REPO_BRANCH ?: 'develop'}"
                REPO_PATH=\$(echo "${env.JENKINS2026_REPO_URL ?: 'https://github.com/nubenetes/jenkins-2026.git'}" | sed -E 's|^https://github.com/||; s|^git@github.com:||; s|\\.git\$||')

                echo -n '{"commit_sha":"' > ${prefix}-payload.json
                echo -n "\$COMMIT_SHA" >> ${prefix}-payload.json
                echo -n '","ref":"' >> ${prefix}-payload.json
                echo -n "\$REF" >> ${prefix}-payload.json
                echo -n '","sarif":"' >> ${prefix}-payload.json
                cat ${prefix}-sarif.b64 >> ${prefix}-payload.json
                echo -n '"}' >> ${prefix}-payload.json

                echo "Uploading ${cfg.toolName} SARIF report to GitHub..."
                RESPONSE=\$(curl -s -o /dev/null -w "%{http_code}" -X POST \\
                  -H "Authorization: token \$GIT_TOKEN" \\
                  -H "Accept: application/vnd.github+json" \\
                  https://api.github.com/repos/\${REPO_PATH}/code-scanning/sarifs \\
                  -d @${prefix}-payload.json)
                echo "GitHub API response for ${cfg.toolName} upload: \$RESPONSE"
                if [ "\$RESPONSE" = "202" ]; then
                     echo "--------------------------------------------------------------------------------"
                     echo "SUCCESS: ${cfg.toolName} SARIF report uploaded to GitHub Code Scanning API!"
                     echo ""
                     echo "WHAT IS ${cfg.toolName.toUpperCase()}?"
${banner}
                     echo ""
                     echo "WHERE CAN I VIEW THE REPORT?"
                     echo "1. GitHub Code Scanning Alerts (Interactive UI with ${cfg.uiDetail}):"
                     echo "   https://github.com/\${REPO_PATH}/security/code-scanning"
                     echo "2. Jenkins Local Workspace (Download raw analysis report):"
                     echo "   \${BUILD_URL}artifact/microservices-src/${cfg.sarifFile}"
                     echo "--------------------------------------------------------------------------------"
                else
                    echo "WARNING: ${cfg.toolName} SARIF upload received unexpected status \$RESPONSE"
                    echo "If this is a fork, ensure GitHub Advanced Security / Code Scanning is enabled."
                fi
                rm -f ${prefix}-sarif.b64 ${prefix}-payload.json
            fi
        """
      }
    }
  }
}

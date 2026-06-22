/**
 * MicroservicesK6SmokePipeline(targetNamespace: '<ns>', envName: 'stable'|'develop',
 *                           genaiEnabled: true|false, vus: '<vus>', iterations: '<iters>')
 *
 * Declarative shared library wrapper for the k6 smoke test pipeline.
 */
def call(Map params) {
    pipeline {
        agent {
            kubernetes {
                yaml """
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins
  containers:
    - name: k6
      image: grafana/k6:2.0.0
      command: ['sleep']
      args: ['infinity']
      # grafana/k6 is a scratch-based binary image; runAsUser: 0 kept until
      # validated that the k6 binary works under a non-root UID in this env.
      securityContext:
        runAsUser: 0
      resources:
        requests: {cpu: 20m, memory: 128Mi}
        limits: {cpu: 500m, memory: 256Mi}
    - name: helm
      image: alpine/k8s:1.31.3
      command: ['sleep']
      args: ['infinity']
      securityContext:
        allowPrivilegeEscalation: false
      env:
        - name: HOME
          value: /tmp
      resources:
        requests: {cpu: 5m, memory: 64Mi}
        limits: {cpu: 100m, memory: 128Mi}
    - name: jnlp
      securityContext:
        allowPrivilegeEscalation: false
      resources:
        requests: {cpu: 10m, memory: 128Mi}
        limits: {cpu: 200m, memory: 256Mi}
"""
            }
        }

        options {
            timestamps()
            buildDiscarder(logRotator(numToKeepStr: '20'))
            disableConcurrentBuilds()
        }

        environment {
            OTEL_SERVICE_NAME = "jenkins-pipeline-k6-smoke"
        }

        stages {
            stage('Checkout Infra') {
                steps {
                    // Use sh git clone inside container('helm') to avoid two issues:
                    // 1. JENKINS-30600: DSL git url: ignores container() wrappers
                    // 2. Full clone in JNLP (256Mi) OOMs; shallow clone in helm (128Mi) does not
                    container('helm') {
                        sh """
                            git config --global --add safe.directory '*' || true
                            find . -mindepth 1 -delete 2>/dev/null || true
                            GIT_LFS_SKIP_SMUDGE=1 git \
                                -c filter.lfs.smudge= \
                                -c filter.lfs.process= \
                                -c filter.lfs.required=false \
                                clone --depth 1 \
                                --branch "${env.JENKINS2026_REPO_BRANCH ?: 'main'}" \
                                "${env.JENKINS2026_REPO_URL ?: 'https://github.com/nubenetes/jenkins-2026.git'}" \
                                .
                        """
                    }
                }
            }
            stage('Run k6 Smoke Test') {
                steps {
                    microservicesK6Smoke(
                        namespace: params.targetNamespace,
                        envName: params.envName,
                        genaiEnabled: params.genaiEnabled,
                        vus: params.vus,
                        iterations: params.iterations
                    )
                }
            }
        }

        post {
            always {
                archiveArtifacts artifacts: 'k6-summary.json', allowEmptyArchive: true
            }
        }
    }
}

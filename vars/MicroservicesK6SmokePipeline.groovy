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
      image: grafana/k6:0.54.0
      command: ['sleep']
      args: ['infinity']
      securityContext:
        runAsUser: 0
      resources:
        requests: {cpu: 20m, memory: 128Mi}
        limits: {cpu: 500m, memory: 256Mi}
    - name: helm
      image: alpine/k8s:1.31.3
      command: ['sleep']
      args: ['infinity']
      resources:
        requests: {cpu: 5m, memory: 64Mi}
        limits: {cpu: 100m, memory: 128Mi}
    - name: jnlp
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
                    withEnv(['GIT_LFS_SKIP_SMUDGE=1']) {
                        git url: "${env.JENKINS2026_REPO_URL ?: 'https://github.com/nubenetes/jenkins-2026.git'}",
                            branch: "${env.JENKINS2026_REPO_BRANCH ?: 'main'}"
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

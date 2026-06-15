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
      resources:
        requests: {cpu: 50m, memory: 128Mi}
        limits: {cpu: 500m, memory: 256Mi}
    - name: helm
      image: alpine/k8s:1.31.3
      command: ['sleep']
      args: ['infinity']
      resources:
        requests: {cpu: 10m, memory: 64Mi}
        limits: {cpu: 100m, memory: 128Mi}
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

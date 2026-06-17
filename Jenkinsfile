// Jenkinsfile
// Declarative DevSecOps Security Pipeline for the jenkins-2026 GKE Platform

pipeline {
    agent {
        kubernetes {
            yaml '''
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins
  containers:
    - name: maven
      image: maven:3.9.9-eclipse-temurin-21
      command: ['sleep']
      args: ['infinity']
      env:
        - name: DOCKER_HOST
          value: tcp://localhost:2375
      resources:
        requests: {cpu: 100m, memory: 1024Mi}
        limits: {cpu: '2', memory: 2.5Gi}
      volumeMounts:
        - name: maven-cache
          mountPath: /root/.m2
    - name: node
      image: node:20-bookworm
      command: ['sleep']
      args: ['infinity']
      env:
        - name: DOCKER_HOST
          value: tcp://localhost:2375
      resources:
        requests: {cpu: 5m, memory: 64Mi}
        limits: {cpu: '100m', memory: 128Mi}
      volumeMounts:
        - name: npm-cache
          mountPath: /root/.npm
    - name: docker
      image: docker:26-dind
      securityContext:
        privileged: true
      env:
        - name: DOCKER_TLS_CERTDIR
          value: ""
      resources:
        requests: {cpu: 20m, memory: 128Mi}
        limits: {cpu: '500m', memory: 512Mi}
    - name: helm
      image: alpine/k8s:1.31.3
      command: ['sleep']
      args: ['infinity']
      env:
        - name: ARGOCD_VERSION
          value: v2.11.0
        - name: ARGOCD_SERVER
          value: "argocd-server.argocd.svc.cluster.local"
      resources:
        requests: {cpu: 5m, memory: 64Mi}
        limits: {cpu: 100m, memory: 128Mi}
    - name: git
      image: alpine/git:latest
      command: ['sleep']
      args: ['infinity']
      resources:
        requests: {cpu: 5m, memory: 64Mi}
        limits: {cpu: 100m, memory: 128Mi}
    - name: semgrep
      image: semgrep/semgrep:1.79.0
      command: ['sleep']
      args: ['infinity']
      resources:
        requests: {cpu: 50m, memory: 256Mi}
        limits: {cpu: '500m', memory: 512Mi}
    - name: codeql
      image: mcr.microsoft.com/cstsectools/codeql-container:latest
      command: ['sleep']
      args: ['infinity']
      securityContext:
        runAsUser: 0
      resources:
        requests: {cpu: 200m, memory: 1024Mi}
        limits: {cpu: '2', memory: 3Gi}
      volumeMounts:
        - name: codeql-cache
          mountPath: /usr/local/codeql-home/.codeql
    - name: trivy
      image: aquasec/trivy:0.52.2
      command: ['sleep']
      args: ['infinity']
      env:
        - name: TRIVY_CACHE_DIR
          value: /tmp/trivy-cache
      resources:
        requests: {cpu: 50m, memory: 256Mi}
        limits: {cpu: '500m', memory: 1Gi}
      volumeMounts:
        - name: trivy-cache
          mountPath: /tmp/trivy-cache
    - name: jnlp
      resources:
        requests: {cpu: 10m, memory: 128Mi}
        limits: {cpu: 200m, memory: 256Mi}
  volumes:
    - name: maven-cache
      hostPath:
        path: /tmp/jenkins-maven-cache
        type: DirectoryOrCreate
    - name: npm-cache
      hostPath:
        path: /tmp/jenkins-npm-cache
        type: DirectoryOrCreate
    - name: trivy-cache
      hostPath:
        path: /tmp/jenkins-trivy-cache
        type: DirectoryOrCreate
    - name: codeql-cache
      hostPath:
        path: /tmp/jenkins-codeql-cache
        type: DirectoryOrCreate
'''
        }
    }

    options {
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
    }

    environment {
        REGISTRY          = "europe-west1-docker.pkg.dev/woven-icon-499218-r9/microservices"
        IMAGE_NAME        = "poc-secure-service"
        IMAGE_TAG         = "latest"
        IMAGE             = "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        OTEL_SERVICE_NAME = "jenkins-poc-devsecops"
    }

    stages {
        stage('Checkout Source') {
            steps {
                checkout scm
            }
        }

        stage('Semgrep SAST') {
            steps {
                container('semgrep') {
                    sh """
                        echo 'Running Semgrep SAST scan...'
                        git config --global --add safe.directory '*' || true
                        semgrep scan --config=p/security-audit --config=p/owasp-top-ten --config=.semgrep/semgrep.yml --sarif --sarif-output=semgrep-results.sarif || true
                    """
                    archiveArtifacts artifacts: 'semgrep-results.sarif', allowEmptyArchive: true
                }
            }
        }

        stage('CodeQL Analysis') {
            steps {
                container('codeql') {
                    sh """
                        echo 'Running CodeQL Static Analysis...'
                        # Initialize CodeQL database for JS/TS (since Gateway contains Angular web frontend)
                        codeql database create codeql-db --language=javascript --source-root=. --threads=0 --ram=2048 --codescanning-config=.github/codeql/codeql-config.yml
                        # Analyze the database
                        codeql database analyze codeql-db --format=sarif-latest --output=codeql-results.sarif --threads=0 --ram=2048 || true
                    """
                    archiveArtifacts artifacts: 'codeql-results.sarif', allowEmptyArchive: true
                }
            }
        }

        stage('Trivy IaC Scan') {
            steps {
                container('trivy') {
                    sh """
                        echo 'Running Trivy IaC configuration misconfiguration checks...'
                        # Scan the Helm charts inside this repository (non-blocking)
                        trivy config --config trivy.yaml --exit-code 0 helm
                    """
                }
            }
        }

        stage('Build & Push Image') {
            steps {
                container('docker') {
                    sh """
                        echo "Building container image locally..."
                        # Create a mock Dockerfile for demonstration
                        echo 'FROM alpine:3.19.1' > Dockerfile.poc
                        echo 'RUN apk add --no-cache curl' >> Dockerfile.poc
                        echo 'CMD ["echo", "PoC Secure Service"]' >> Dockerfile.poc

                        # Build container image
                        docker build -t ${IMAGE} -f Dockerfile.poc .
                        rm Dockerfile.poc
                        echo "Image built successfully: ${IMAGE}"
                    """
                }
            }
        }

        stage('Trivy Image Scan') {
            steps {
                container('trivy') {
                    sh """
                        echo 'Running Trivy Vulnerability Scan on built container image...'
                        trivy image --config trivy.yaml --exit-code 1 --severity CRITICAL,HIGH ${IMAGE}
                    """
                }
            }
        }

        stage('Update GitOps Manifest') {
            steps {
                container('git') {
                    sh """
                        echo "Updating GitOps tag to ${IMAGE_TAG} in Helm values..."
                        echo "chore(ops): update image tag to ${IMAGE_TAG} (simulated)"
                    """
                }
            }
        }
    }
}

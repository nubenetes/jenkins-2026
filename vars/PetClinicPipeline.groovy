/**
 * PetClinicPipeline(serviceName: '<svc>', serviceType: 'java'|'angular',
 *                    modulePath: '<maven-module>', gitRepoUrl: '<repo>',
 *                    gitBranch: '<branch>', targetNamespace: '<ns>',
 *                    envName: 'stable'|'develop', port: '<port>',
 *                    healthPath: '<path>', platform: '<platform>')
 *
 * Declarative shared library wrapper for the standard PetClinic build/deploy pipeline.
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
    - name: maven
      image: maven:3.9.9-eclipse-temurin-17
      command: ['sleep']
      args: ['infinity']
      env:
        - name: DOCKER_HOST
          value: tcp://localhost:2375
      resources:
        requests: {cpu: 200m, memory: 1Gi}
        limits: {cpu: '2', memory: 3Gi}
    - name: node
      image: node:20-bookworm
      command: ['sleep']
      args: ['infinity']
      env:
        - name: DOCKER_HOST
          value: tcp://localhost:2375
      resources:
        requests: {cpu: 50m, memory: 512Mi}
        limits: {cpu: '2', memory: 2Gi}
    - name: docker
      image: docker:26-dind
      securityContext:
        privileged: true
      env:
        - name: DOCKER_TLS_CERTDIR
          value: ""
      resources:
        requests: {cpu: 100m, memory: 512Mi}
        limits: {cpu: '2', memory: 2Gi}
    - name: helm
      image: alpine/k8s:1.31.3
      command: ['sleep']
      args: ['infinity']
      env:
        - name: ARGOCD_VERSION
          value: v2.11.0
      resources:
        requests: {cpu: 50m, memory: 256Mi}
        limits: {cpu: 500m, memory: 512Mi}
    - name: git
      image: alpine/git:latest
      command: ['sleep']
      args: ['infinity']
      resources:
        requests: {cpu: 50m, memory: 128Mi}
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
            REGISTRY      = "${env.PETCLINIC_REGISTRY ?: 'ghcr.io/nubenetes/jenkins-2026-petclinic'}"
            IMAGE_TAG     = "${params.gitBranch}"
            IMAGE         = "${env.REGISTRY}/${params.serviceName}:${env.IMAGE_TAG}"
            OTEL_SERVICE_NAME = "jenkins-pipeline-${params.serviceName}"
        }

        stages {
            stage('Checkout PetClinic source') {
                steps {
                    dir('petclinic-src') {
                        git url: params.gitRepoUrl, branch: params.gitBranch
                    }
                }
            }

            stage('Build & Test') {
                steps {
                    dir('petclinic-src') {
                        petclinicBuild(type: params.serviceType, module: params.modulePath)
                    }
                }
            }

            stage('Build & Push Image') {
                steps {
                    dir('petclinic-src') {
                        petclinicImage(
                            type: params.serviceType,
                            module: params.modulePath,
                            image: env.IMAGE,
                            registryHost: env.REGISTRY.tokenize('/')[0]
                        )
                    }
                }
            }

            stage('Deploy to Kubernetes') {
                steps {
                    petclinicDeploy(
                        serviceName: params.serviceName,
                        envName: params.envName,
                        namespace: params.targetNamespace,
                        platform: params.platform,
                        tag: env.IMAGE_TAG
                    )
                }
            }

            stage('Smoke Test') {
                steps {
                    petclinicSmokeTest(
                        serviceName: params.serviceName,
                        namespace: params.targetNamespace,
                        port: params.port,
                        healthPath: params.healthPath
                    )
                }
            }
        }

        post {
            always {
                junit testResults: 'petclinic-src/**/target/surefire-reports/*.xml', allowEmptyResults: true
            }
        }
    }
}

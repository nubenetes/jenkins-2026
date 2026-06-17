/**
 * MicroservicesPipeline(serviceName: '<svc>', serviceType: 'java'|'angular',
 *                    modulePath: '<maven-module>', gitRepoUrl: '<repo>',
 *                    gitBranch: '<branch>', targetNamespace: '<ns>',
 *                    envName: 'stable'|'develop', port: '<port>',
 *                    healthPath: '<path>', platform: 'gke')
 *
 * Declarative shared library wrapper for the standard Microservices build/deploy pipeline.
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
          value: "${env.ARGOCD_SERVER ?: 'argocd-server.argocd.svc.cluster.local'}"
        - name: ARGOCD_AUTH_TOKEN
          valueFrom:
            secretKeyRef:
              name: jenkins-credentials
              key: argocd-token
              optional: true
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
"""
            }
        }

        options {
            timestamps()
            buildDiscarder(logRotator(numToKeepStr: '20'))
            disableConcurrentBuilds()
        }

        environment {
            REGISTRY      = "${env.MICROSERVICES_REGISTRY ?: 'ghcr.io/nubenetes/jenkins-2026-microservices'}"
            IMAGE_TAG     = "${params.gitBranch}"
            IMAGE         = "${env.REGISTRY}/${params.serviceName}:${env.IMAGE_TAG}"
            OTEL_SERVICE_NAME = "jenkins-pipeline-${params.serviceName}"
        }

        stages {
            stage('Checkout Microservices source') {
                steps {
                    dir('microservices-src') {
                        git url: params.gitRepoUrl, branch: params.gitBranch
                        script {
                            if (params.serviceName == 'gateway') {
                                sh """
                                    echo 'Patching gateway User.java to remove Hibernate Cache annotations...'
                                    if [ -f src/main/java/io/github/jhipster/sample/domain/User.java ]; then
                                        sed -i '/org.hibernate.annotations.Cache/d' src/main/java/io/github/jhipster/sample/domain/User.java
                                        sed -i '/@Cache(usage = CacheConcurrencyStrategy/d' src/main/java/io/github/jhipster/sample/domain/User.java
                                    fi
                                    echo 'Patching gateway UserRepository.java to declare missing cache constants...'
                                    if [ -f src/main/java/io/github/jhipster/sample/repository/UserRepository.java ]; then
                                        sed -i '/public interface UserRepository/a \\    String USERS_BY_LOGIN_CACHE = "usersByLogin";\\n    String USERS_BY_EMAIL_CACHE = "usersByEmail";' src/main/java/io/github/jhipster/sample/repository/UserRepository.java
                                    fi
                                    echo 'Patching gateway pom.xml to replace MySQL with PostgreSQL...'
                                    if [ -f pom.xml ]; then
                                        sed -i 's|<groupId>com.mysql</groupId>|<groupId>org.postgresql</groupId>|g' pom.xml
                                        sed -i 's|<artifactId>mysql-connector-j</artifactId>|<artifactId>postgresql</artifactId>|g' pom.xml
                                        sed -i 's|<groupId>io.asyncer</groupId>|<groupId>org.postgresql</groupId>|g' pom.xml
                                        sed -i 's|<artifactId>r2dbc-mysql</artifactId>|<artifactId>r2dbc-postgresql</artifactId>|g' pom.xml
                                        sed -i 's|<artifactId>mysql</artifactId>|<artifactId>postgresql</artifactId>|g' pom.xml
                                        sed -i 's|<liquibase-plugin.driver>com.mysql.cj.jdbc.Driver</liquibase-plugin.driver>|<liquibase-plugin.driver>org.postgresql.Driver</liquibase-plugin.driver>|g' pom.xml
                                        sed -i 's|<liquibase-plugin.hibernate-dialect>org.hibernate.dialect.MySQL8Dialect</liquibase-plugin.hibernate-dialect>|<liquibase-plugin.hibernate-dialect>org.hibernate.dialect.PostgreSQLDialect</liquibase-plugin.hibernate-dialect>|g' pom.xml
                                        sed -i 's|jdbc:mysql://localhost:3306/jhipsterSampleGateway|jdbc:postgresql://localhost:5432/jhipsterSampleGateway|g' pom.xml
                                    fi
                                    echo 'Patching application-prod.yml to use PostgreSQL URL formats...'
                                    if [ -f src/main/resources/config/application-prod.yml ]; then
                                        sed -i 's|jdbc:mysql://localhost:3306/jhipsterSampleGateway.*|jdbc:postgresql://localhost:5432/jhipsterSampleGateway|g' src/main/resources/config/application-prod.yml
                                        sed -i 's|r2dbc:mysql://localhost:3306/jhipsterSampleGateway.*|r2dbc:postgresql://localhost:5432/jhipsterSampleGateway|g' src/main/resources/config/application-prod.yml
                                    fi
                                    echo 'Creating gateway CacheConfiguration.java to define NoOpCacheManager bean...'
                                    mkdir -p src/main/java/io/github/jhipster/sample/config
                                    cat << 'EOF' > src/main/java/io/github/jhipster/sample/config/CacheConfiguration.java
package io.github.jhipster.sample.config;

import org.springframework.cache.CacheManager;
import org.springframework.cache.annotation.EnableCaching;
import org.springframework.cache.support.NoOpCacheManager;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
@EnableCaching
public class CacheConfiguration {

    @Bean
    public CacheManager cacheManager() {
        return new NoOpCacheManager();
    }
}
EOF
                                """
                            }
                        }
                    }
                }
            }

            stage('Build & Test') {
                steps {
                    dir('microservices-src') {
                        microservicesBuild(type: params.serviceType, module: params.modulePath)
                    }
                }
            }

            stage('Build & Push Image') {
                steps {
                    dir('microservices-src') {
                        microservicesImage(
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
                    microservicesDeploy(
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
                    microservicesSmokeTest(
                        serviceName: params.serviceName,
                        namespace: params.targetNamespace,
                        port: params.port,
                        healthPath: params.healthPath
                    )
                }
            }

            stage('Integration k6 Smoke Test') {
                steps {
                    script {
                        def k6JobName = 'microservices-k6-smoke'
                        echo "Triggering integration k6 smoke test: ${k6JobName}..."
                        build job: k6JobName, wait: true
                    }
                }
            }
        }

        post {
            always {
                junit testResults: 'microservices-src/**/target/surefire-reports/*.xml', allowEmptyResults: true
            }
        }
    }
}

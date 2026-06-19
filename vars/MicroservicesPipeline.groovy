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
        requests: {cpu: '1.0', memory: 2.0Gi}
        limits: {cpu: '4', memory: 4.0Gi}
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
      # runAsUser: 1000 matches the jenkins user in the jnlp container so
      # files cloned here can be deleted by jnlp/maven without EPERM.
      securityContext:
        runAsUser: 1000
      resources:
        requests: {cpu: 5m, memory: 128Mi}
        limits: {cpu: 100m, memory: 512Mi}
    - name: semgrep
      image: semgrep/semgrep:1.79.0
      command: ['sleep']
      args: ['infinity']
      resources:
        requests: {cpu: 200m, memory: 512Mi}
        limits: {cpu: '2', memory: 2.0Gi}
    - name: codeql
      image: mcr.microsoft.com/cstsectools/codeql-container:latest
      command: ['sleep']
      args: ['infinity']
      securityContext:
        runAsUser: 0
      resources:
        requests: {cpu: 500m, memory: 512Mi}
        limits: {cpu: '4', memory: 4.0Gi}
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
        - name: GOGC
          value: "20"
      resources:
        requests: {cpu: 200m, memory: 512Mi}
        limits: {cpu: '2', memory: 4.0Gi}
      volumeMounts:
        - name: trivy-cache
          mountPath: /tmp/trivy-cache
    - name: jnlp
      resources:
        requests: {cpu: 10m, memory: 128Mi}
        limits: {cpu: 200m, memory: 256Mi}
  tolerations:
    - key: "jenkins-agent"
      operator: "Equal"
      value: "true"
      effect: "NoSchedule"
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

            stage('Checkout Infra configs') {
                steps {
                    container('git') {
                        // Use sh (not the git DSL step) so container() is honoured.
                        // The DSL git step triggers JENKINS-30600 and runs in jnlp
                        // instead, where 256Mi is insufficient for this repo's objects.
                        // -c filter.lfs.* bypasses the LFS filter entirely without
                        // requiring git-lfs to be installed in the alpine/git image.
                        sh """
                            git config --global --add safe.directory '*' || true
                            rm -rf jenkins-2026-infra
                            GIT_LFS_SKIP_SMUDGE=1 git \
                                -c filter.lfs.smudge= \
                                -c filter.lfs.process= \
                                -c filter.lfs.required=false \
                                clone --depth 1 \
                                --branch ${env.JENKINS2026_REPO_BRANCH ?: 'main'} \
                                ${env.JENKINS2026_REPO_URL ?: 'https://github.com/nubenetes/jenkins-2026.git'} \
                                jenkins-2026-infra
                        """
                    }
                }
            }

            stage('Semgrep SAST') {
                steps {
                    container('semgrep') {
                        dir('microservices-src') {
                            sh """
                                git config --global --add safe.directory '*' || true
                                semgrep scan --config=p/security-audit --config=p/owasp-top-ten --config=${env.WORKSPACE}/jenkins-2026-infra/.semgrep/semgrep.yml --sarif --sarif-output=semgrep-results.sarif . || true
                            """
                            archiveArtifacts artifacts: 'semgrep-results.sarif', allowEmptyArchive: true
                        }
                    }
                    container('git') {
                        dir('microservices-src') {
                            withCredentials([usernamePassword(credentialsId: 'microservices-git', 
                                                             passwordVariable: 'GIT_TOKEN', 
                                                             usernameVariable: 'GIT_USER')]) {
                                sh """
                                    git config --global --add safe.directory '*' || true
                                    apk add --no-cache curl || true
                                    if [ -f semgrep-results.sarif ]; then
                                        echo "Preparing Semgrep SARIF report payload..."
                                        gzip -c semgrep-results.sarif | base64 -w0 > semgrep-sarif.b64
                                        COMMIT_SHA=\$(git -C ${env.WORKSPACE}/jenkins-2026-infra rev-parse HEAD | tr -d '\\n')
                                        REF="refs/heads/${env.JENKINS2026_REPO_BRANCH ?: 'develop'}"
                                        REPO_PATH=\$(echo "${env.JENKINS2026_REPO_URL ?: 'https://github.com/nubenetes/jenkins-2026.git'}" | sed -E 's|^https://github.com/||; s|^git@github.com:||; s|\\.git\$||')
                                        
                                        echo -n '{"commit_sha":"' > semgrep-payload.json
                                        echo -n "\$COMMIT_SHA" >> semgrep-payload.json
                                        echo -n '","ref":"' >> semgrep-payload.json
                                        echo -n "\$REF" >> semgrep-payload.json
                                        echo -n '","sarif":"' >> semgrep-payload.json
                                        cat semgrep-sarif.b64 >> semgrep-payload.json
                                        echo -n '"}' >> semgrep-payload.json
                                        
                                        echo "Uploading Semgrep SARIF report to GitHub..."
                                        RESPONSE=\$(curl -s -o /dev/null -w "%{http_code}" -X POST \\
                                          -H "Authorization: token \$GIT_TOKEN" \\
                                          -H "Accept: application/vnd.github+json" \\
                                          https://api.github.com/repos/\${REPO_PATH}/code-scanning/sarifs \\
                                          -d @semgrep-payload.json)
                                        echo "GitHub API response for Semgrep upload: \$RESPONSE"
                                        if [ "\$RESPONSE" = "202" ]; then
                                             echo "--------------------------------------------------------------------------------"
                                             echo "SUCCESS: Semgrep SARIF report uploaded to GitHub Code Scanning API!"
                                             echo ""
                                             echo "WHAT IS SEMGREP?"
                                             echo "Semgrep is a fast, open-source static analysis tool for finding bugs,"
                                             echo "detecting vulnerabilities, and enforcing code standards during development."
                                             echo "It uses syntax-aware pattern matching without needing a build step."
                                             echo ""
                                             echo "WHERE CAN I VIEW THE REPORT?"
                                             echo "1. GitHub Code Scanning Alerts (Interactive UI with code mappings):"
                                             echo "   https://github.com/\${REPO_PATH}/security/code-scanning"
                                             echo "2. Jenkins Local Workspace (Download raw analysis report):"
                                             echo "   \${BUILD_URL}artifact/microservices-src/semgrep-results.sarif"
                                             echo "--------------------------------------------------------------------------------"
                                        else
                                            echo "WARNING: Semgrep SARIF upload received unexpected status \$RESPONSE"
                                            echo "If this is a fork, ensure GitHub Advanced Security / Code Scanning is enabled."
                                        fi
                                        rm -f semgrep-sarif.b64 semgrep-payload.json
                                    fi
                                """
                            }
                        }
                    }
                }
            }

            stage('CodeQL Analysis') {
                steps {
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
                    container('git') {
                        dir('microservices-src') {
                            withCredentials([usernamePassword(credentialsId: 'microservices-git', 
                                                             passwordVariable: 'GIT_TOKEN', 
                                                             usernameVariable: 'GIT_USER')]) {
                                sh """
                                    git config --global --add safe.directory '*' || true
                                    apk add --no-cache curl || true
                                    if [ -f codeql-results.sarif ]; then
                                        echo "Preparing CodeQL SARIF report payload..."
                                        gzip -c codeql-results.sarif | base64 -w0 > codeql-sarif.b64
                                        COMMIT_SHA=\$(git -C ${env.WORKSPACE}/jenkins-2026-infra rev-parse HEAD | tr -d '\\n')
                                        REF="refs/heads/${env.JENKINS2026_REPO_BRANCH ?: 'develop'}"
                                        REPO_PATH=\$(echo "${env.JENKINS2026_REPO_URL ?: 'https://github.com/nubenetes/jenkins-2026.git'}" | sed -E 's|^https://github.com/||; s|^git@github.com:||; s|\\.git\$||')
                                        
                                        echo -n '{"commit_sha":"' > codeql-payload.json
                                        echo -n "\$COMMIT_SHA" >> codeql-payload.json
                                        echo -n '","ref":"' >> codeql-payload.json
                                        echo -n "\$REF" >> codeql-payload.json
                                        echo -n '","sarif":"' >> codeql-payload.json
                                        cat codeql-sarif.b64 >> codeql-payload.json
                                        echo -n '"}' >> codeql-payload.json
                                        
                                        echo "Uploading CodeQL SARIF report to GitHub..."
                                        RESPONSE=\$(curl -s -o /dev/null -w "%{http_code}" -X POST \\
                                          -H "Authorization: token \$GIT_TOKEN" \\
                                          -H "Accept: application/vnd.github+json" \\
                                          https://api.github.com/repos/\${REPO_PATH}/code-scanning/sarifs \\
                                          -d @codeql-payload.json)
                                        echo "GitHub API response for CodeQL upload: \$RESPONSE"
                                        if [ "\$RESPONSE" = "202" ]; then
                                             echo "--------------------------------------------------------------------------------"
                                             echo "SUCCESS: CodeQL SARIF report uploaded to GitHub Code Scanning API!"
                                             echo ""
                                             echo "WHAT IS CODEQL?"
                                             echo "CodeQL is GitHub's advanced semantic code analysis engine. By treating"
                                             echo "code as data, it executes queries to detect security vulnerabilities,"
                                             echo "data flow anomalies, and structural issues in your application stack."
                                             echo ""
                                             echo "WHERE CAN I VIEW THE REPORT?"
                                             echo "1. GitHub Code Scanning Alerts (Interactive UI with data flow paths):"
                                             echo "   https://github.com/\${REPO_PATH}/security/code-scanning"
                                             echo "2. Jenkins Local Workspace (Download raw analysis report):"
                                             echo "   \${BUILD_URL}artifact/microservices-src/codeql-results.sarif"
                                             echo "--------------------------------------------------------------------------------"
                                        else
                                            echo "WARNING: CodeQL SARIF upload received unexpected status \$RESPONSE"
                                            echo "If this is a fork, ensure GitHub Advanced Security / Code Scanning is enabled."
                                        fi
                                        rm -f codeql-sarif.b64 codeql-payload.json
                                    fi
                                """
                            }
                        }
                    }
                }
            }

            stage('Trivy IaC Scan') {
                steps {
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
                                    --branch ${params.envName == 'stable' ? 'main' : 'develop'} \
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

            stage('Trivy Image Scan') {
                steps {
                    withCredentials([usernamePassword(credentialsId: 'container-registry', usernameVariable: 'TRIVY_USERNAME', passwordVariable: 'TRIVY_PASSWORD')]) {
                        container('trivy') {
                            sh """
                                trivy image --scanners vuln --config ${env.WORKSPACE}/jenkins-2026-infra/trivy.yaml --exit-code 0 --severity CRITICAL,HIGH ${env.IMAGE}
                            """
                        }
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
                recordIssues(
                    enabledForFailure: true,
                    aggregatingResults: true,
                    tools: [
                        sarif(pattern: 'microservices-src/semgrep-results.sarif', id: 'semgrep', name: 'Semgrep'),
                        sarif(pattern: 'microservices-src/codeql-results.sarif', id: 'codeql', name: 'CodeQL')
                    ]
                )
            }
        }
    }
}

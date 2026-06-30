/**
 * MicroservicesPipeline(serviceName: '<svc>', serviceType: 'java'|'angular',
 *                    modulePath: '<maven-module>', gitRepoUrl: '<repo>',
 *                    gitBranch: '<branch>', targetNamespace: '<ns>',
 *                    envName: 'stable'|'develop', port: '<port>',
 *                    healthPath: '<path>', platform: 'gke')
 *
 * Declarative shared library wrapper for the standard Microservices build/deploy pipeline.
 */
def call(Map cfg) {
    // Build-agent node placement — config flag jenkins.runNodePool, surfaced via JCasC as
    // env.RUN_NODE_POOL (static | ci-spot; default static):
    //   static  -> the long-lived jenkins-2026-pool (nodeSelector app=jenkins-2026): robust,
    //              always present, no NAP/Spot/quota dependency.
    //   ci-spot -> the NAP Spot ComputeClass (env.GKE_COMPUTE_CLASS): ephemeral, scale-to-zero;
    //              GKE auto-taints those pools, hence the tolerations. A Spot preemption just
    //              restarts this build (fine for Jenkins's single agent pod).
    // ci-spot needs nodeAutoProvisioning enabled (GKE_COMPUTE_CLASS set); if it's empty we fall
    // back to static. See infrastructure/compute-classes/ + docs/201 + docs/501.
    String runPool = (env.RUN_NODE_POOL ?: 'static').trim()
    String computeClass = (env.GKE_COMPUTE_CLASS ?: '').trim()
    String agentNodeScheduling = (runPool == 'ci-spot' && computeClass) ? """
  nodeSelector:
    cloud.google.com/compute-class: ${computeClass}
  tolerations:
    - key: cloud.google.com/compute-class
      operator: Equal
      value: "${computeClass}"
      effect: NoSchedule
    - key: cloud.google.com/gke-spot
      operator: Equal
      value: "true"
      effect: NoSchedule""" : """
  nodeSelector:
    app: jenkins-2026"""
    pipeline {
        agent {
            kubernetes {
                // Keep the agent pod warm ~5 min after the build so a re-run / the next
                // service's build REUSES it instead of cold-starting a fresh 8-container
                // pod (pod schedule + multi-image pull + JNLP connect is the slow part).
                idleMinutes 5
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
      # TODO: migrate to bitnami/maven (UID 1001) once /root/.m2 cache path is moved
      securityContext:
        allowPrivilegeEscalation: false
      env:
        - name: DOCKER_HOST
          value: tcp://localhost:2375
      # Sized for the JHipster build (microservicesBuild.groovy runs `mvnw -T 4 clean verify`):
      # the Maven JVM (MAVEN_OPTS -Xmx) PLUS up to 4 parallel module builds, each forking a
      # test JVM (-Xmx1536m). At 4Gi this overcommitted → OOM/GC-thrash → slow builds. 8Gi
      # gives headroom for -T 4 + forked tests; 6 CPU lets the 4 threads + scanners run.
      resources:
        requests: {cpu: '2', memory: 4.0Gi}
        limits: {cpu: '6', memory: 8.0Gi}
      # In-Place Pod Resize (K8s 1.33+ GA; cluster 1.35) — grow under load without a restart.
      resizePolicy:
        - {resourceName: cpu, restartPolicy: NotRequired}
        - {resourceName: memory, restartPolicy: NotRequired}
      volumeMounts:
        - name: maven-cache
          mountPath: /root/.m2
    - name: node
      image: node:20-bookworm
      command: ['sleep']
      args: ['infinity']
      # TODO: migrate to runAsUser: 1000 (built-in 'node' user) once /root/.npm cache path is moved
      securityContext:
        allowPrivilegeEscalation: false
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
      # DinD requires privileged + root — cannot be reduced without rootless Docker
      securityContext:
        privileged: true
        runAsUser: 0
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
      # runAsUser: 1000 matches the git container so yq can write git-cloned
      # files (same UID = write permission). HOME=/tmp lets argocd CLI write
      # its config cache without needing root.
      securityContext:
        runAsUser: 1000
        runAsNonRoot: true
        allowPrivilegeEscalation: false
      env:
        - name: HOME
          value: /tmp
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
      image: alpine/git:2.54.0
      command: ['sleep']
      args: ['infinity']
      # runAsUser: 1000 overrides the image default (root). Kubernetes enforces
      # the UID at runtime so the process genuinely runs as non-root even though
      # alpine/git has no passwd entry for 1000. HOME=/tmp is required because
      # alpine has no /home/1000 — git config --global writes to /tmp/.gitconfig
      # (container-local, not shared with other containers).
      # runAsUser 1000 also matches the jnlp/jenkins UID so files created here
      # are accessible to the jnlp container without permission errors.
      securityContext:
        runAsUser: 1000
        runAsNonRoot: true
        allowPrivilegeEscalation: false
      env:
        - name: HOME
          value: /tmp
      resources:
        requests: {cpu: 5m, memory: 128Mi}
        limits: {cpu: 100m, memory: 512Mi}
    - name: semgrep
      image: semgrep/semgrep:1.79.0
      command: ['sleep']
      args: ['infinity']
      securityContext:
        allowPrivilegeEscalation: false
      resources:
        requests: {cpu: 200m, memory: 512Mi}
        limits: {cpu: '2', memory: 2.0Gi}
    - name: codeql
      # Pinned by digest (matches the Tekton codeql-analyze task) - this image
      # publishes no version tags, so :latest was the only floating one left.
      image: mcr.microsoft.com/cstsectools/codeql-container:c6f3f8cbd3e0ebc36d9ad6dfe6a4c166ba940166
      command: ['sleep']
      args: ['infinity']
      # Requires root: installs Node.js via apt-get and runs CodeQL analysis
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
      # TODO: add runAsUser once hostPath trivy-cache dir ownership is initialised
      securityContext:
        allowPrivilegeEscalation: false
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
      securityContext:
        allowPrivilegeEscalation: false
      resources:
        requests: {cpu: 10m, memory: 128Mi}
        limits: {cpu: 200m, memory: 256Mi}
${agentNodeScheduling}
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
            // Immutable, traceable tag: <branch>-<build#> (e.g. develop-42) instead of a
            // mutable branch tag that every build overwrites. Each build publishes a unique
            // tag, GitOps Update pins values-<env>.yaml to it, and ArgoCD deploys that exact
            // build — so a deploy is reproducible and rollback = repoint to a prior tag.
            // BUILD_NUMBER is available at pipeline start (no checkout needed).
            IMAGE_TAG     = "${cfg.gitBranch}-${env.BUILD_NUMBER}"
            IMAGE         = "${env.REGISTRY}/${cfg.serviceName}:${env.IMAGE_TAG}"
            OTEL_SERVICE_NAME = "jenkins-pipeline-${cfg.serviceName}"
        }

        stages {
            stage('Checkout Microservices source') {
                steps {
                    dir('microservices-src') {
                        // Shallow, single-branch, no-tags clone. The plain `git` step
                        // fetched ALL history + every branch ref + tags of the (large
                        // JHipster) app repo — the slow part of "Checkout". depth:1 +
                        // noTags + single branch is dramatically faster (we only build
                        // the tip of one branch). Not the agent scheduling (pods are
                        // warmed by the prepull DaemonSet + idleMinutes reuse).
                        checkout([
                            $class: 'GitSCM',
                            branches: [[name: "*/${cfg.gitBranch}"]],
                            userRemoteConfigs: [[url: cfg.gitRepoUrl]],
                            extensions: [
                                [$class: 'CloneOption', shallow: true, depth: 1, noTags: true, honorRefspec: true],
                                [$class: 'CheckoutOption', timeout: 20],
                            ],
                        ])
                        script {
                            if (cfg.serviceName == 'gateway') {
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
                    // Upload SARIF in container('helm') — alpine/k8s has curl, git,
                    // gzip, and base64 pre-installed so no package install needed.
                    // container('git') (alpine/git + runAsUser:1000) cannot install
                    // packages (apk requires root) and lacks curl.
                    container('helm') {
                        dir('microservices-src') {
                            withCredentials([usernamePassword(credentialsId: 'microservices-git',
                                                             passwordVariable: 'GIT_TOKEN',
                                                             usernameVariable: 'GIT_USER')]) {
                                sh """
                                    git config --global --add safe.directory '*' || true
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
                    // Upload SARIF in container('helm') — alpine/k8s has curl, git,
                    // gzip, and base64 pre-installed so no package install needed.
                    // container('git') (alpine/git + runAsUser:1000) cannot run
                    // apk add as non-root, so curl is unavailable there.
                    container('helm') {
                        dir('microservices-src') {
                            withCredentials([usernamePassword(credentialsId: 'microservices-git',
                                                             passwordVariable: 'GIT_TOKEN',
                                                             usernameVariable: 'GIT_USER')]) {
                                sh """
                                    git config --global --add safe.directory '*' || true
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
                                    --branch ${cfg.envName == 'stable' ? 'main' : 'develop'} \
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
                        microservicesBuild(type: cfg.serviceType, module: cfg.modulePath)
                    }
                }
            }

            stage('Build & Push Image') {
                steps {
                    dir('microservices-src') {
                        microservicesImage(
                            type: cfg.serviceType,
                            module: cfg.modulePath,
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
                        serviceName: cfg.serviceName,
                        envName: cfg.envName,
                        namespace: cfg.targetNamespace,
                        platform: cfg.platform,
                        tag: env.IMAGE_TAG
                    )
                }
            }

            stage('Smoke Test') {
                steps {
                    microservicesSmokeTest(
                        serviceName: cfg.serviceName,
                        namespace: cfg.targetNamespace,
                        port: cfg.port,
                        healthPath: cfg.healthPath
                    )
                }
            }

            stage('Integration k6 Smoke Test') {
                steps {
                    script {
                        // Trigger the k6 job for THIS tier: 'develop' deploys to the
                        // microservices-develop namespace, so it must hand off to the
                        // 'microservices-k6-smoke-develop' job (the seed generates one
                        // k6 job per environment). Previously hardcoded to the stable
                        // job, which smoke-tested the wrong namespace on develop runs.
                        def k6Suffix = cfg.envName == 'develop' ? '-develop' : ''
                        def k6JobName = "microservices-k6-smoke${k6Suffix}"
                        echo "Triggering integration k6 smoke test: ${k6JobName} (env=${cfg.envName}, ns=${cfg.targetNamespace})..."
                        // Pass TARGET_NAMESPACE/ENV_NAME explicitly rather than relying on the
                        // k6 job's parameter defaults: Jenkins does NOT apply a declarative
                        // job's default parameter values on its FIRST build after the seed
                        // (re)defines it, so a default-only trigger sent namespace="null"
                        // (-> gateway.null.svc, 100% request failures). Explicit params are
                        // robust on first build, re-seeds and manual runs alike.
                        build job: k6JobName, wait: true, parameters: [
                            string(name: 'TARGET_NAMESPACE', value: cfg.targetNamespace),
                            string(name: 'ENV_NAME', value: cfg.envName)
                        ]
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

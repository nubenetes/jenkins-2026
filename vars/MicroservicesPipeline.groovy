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
    //              GKE auto-taints those pools, hence the tolerations. A Spot preemption is
    //              auto-retried on a fresh pod by the agent's `retries 2` below.
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
    // Binary Authorization image signing (opt-in, docs/507). Only when the flag is on,
    // append a lightweight google/cloud-sdk container to the agent pod so
    // microservicesImage.groovy can sign the pushed image via its Workload Identity.
    // Off by default → zero extra container, zero cost. env.BINAUTHZ_ENABLED is threaded
    // by JCasC (04-jenkins.sh) from J2026_BINARY_AUTHORIZATION_ENABLED.
    String binauthzContainer = (env.BINAUTHZ_ENABLED == 'true') ? """
    - name: gcloud
      image: google/cloud-sdk:slim
      command: ['sleep']
      args: ['infinity']
      securityContext:
        allowPrivilegeEscalation: false
      resources:
        requests: {cpu: 5m, memory: 64Mi}
        limits: {cpu: '200m', memory: 256Mi}""" : ""
    // Per-tier k6 handoff target, resolved here (cfg is static config) so the
    // 'Integration k6 Smoke Test' stage below needs no script {} block.
    String k6JobName = "microservices-k6-smoke${cfg.envName == 'develop' ? '-develop' : ''}"
    pipeline {
        agent {
            kubernetes {
                // Keep the agent pod warm ~5 min after the build so a re-run / the next
                // service's build REUSES it instead of cold-starting a fresh 9-container
                // pod (pod schedule + multi-image pull + JNLP connect is the slow part).
                idleMinutes 5
                // Official pod-loss auto-retry (kubernetes plugin): if the agent pod
                // dies for an infrastructure reason — the ci-spot Spot preemption,
                // a node drain/eviction — the whole run is retried once on a fresh
                // pod. Qualifying failures only (kubernetesAgent + nonresumable
                // conditions under the hood): a compile/test failure is NOT retried.
                // Safe: every stage is idempotent (same IMAGE_TAG re-pushed, gitops
                // bump converges to "No changes to commit", argocd sync re-syncs).
                retries 2
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
        limits: {cpu: '500m', memory: 512Mi}${binauthzContainer}
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
            // Safety net: a hung stage (wedged argocd wait, stuck image pull, ...)
            // must release the agent and the disableConcurrentBuilds queue slot.
            // Worst honest run (cold caches + gateway ~600s startupProbe + k6
            // smoke handoff) is well under an hour; 120 min only fires on hangs.
            timeout(time: 120, unit: 'MINUTES')
            // jenkins.io "Scaling Pipelines" recommendation for re-runnable
            // build/test pipelines: ~2-6x less controller disk I/O. Trade-off:
            // a hard controller crash mid-build cannot resume the run — fine
            // here (idempotent stages, ephemeral Jenkins home) and pod-loss is
            // already covered by the agent-level `retries 2` above.
            durabilityHint('PERFORMANCE_OPTIMIZED')
        }

        environment {
            REGISTRY      = "${env.MICROSERVICES_REGISTRY ?: 'ghcr.io/nubenetes/jenkins-2026-microservices'}"
            // IMAGE_TAG / IMAGE are deliberately NOT declared here: variables
            // from this directive wrap every stage in a withEnv overlay that
            // SHADOWS any later `env.X = ...` mutation from a script {} block —
            // so the Checkout stage's rebuild-safe SHA suffix silently never
            // reached the build/push/deploy stages (found live 2026-07-11; the
            // shadowing was latent while bug #1, the empty GIT_COMMIT, kept the
            // mutation path from ever running). Both are set once, in the
            // Checkout stage's script island, and read as plain env everywhere.
            OTEL_SERVICE_NAME = "jenkins-pipeline-${cfg.serviceName}"
        }

        stages {
            stage('Checkout Microservices source') {
                steps {
                    dir('microservices-src') {
                        script {
                            // Shallow, single-branch, no-tags clone. The plain `git` step
                            // fetched ALL history + every branch ref + tags of the (large
                            // JHipster) app repo — the slow part of "Checkout". depth:1 +
                            // noTags + single branch is dramatically faster (we only build
                            // the tip of one branch). Not the agent scheduling (pods are
                            // warmed by the prepull DaemonSet + idleMinutes reuse).
                            //
                            // Rebuild-safety (see IMAGE_TAG comment): append the app-source
                            // commit SHA so the tag is unique across Jenkins incarnations
                            // even after BUILD_NUMBER resets. The SHA comes from checkout's
                            // RETURN MAP — env.GIT_COMMIT is only auto-populated on
                            // single-checkout builds, and this build also clones the infra
                            // + gitops repos, so the env var arrives EMPTY (found live
                            // 2026-07-11: tags shipped as <branch>-<build#> and re-minted
                            // main-1 across incarnations, the exact #488 collision).
                            // (This is the pipeline's one script {} island: mutating env
                            // for all later stages from a runtime-born value has no
                            // declarative directive equivalent — docs/403 §7.6 Case 1.)
                            def scmVars = checkout([
                                $class: 'GitSCM',
                                branches: [[name: "*/${cfg.gitBranch}"]],
                                userRemoteConfigs: [[url: cfg.gitRepoUrl]],
                                extensions: [
                                    [$class: 'CloneOption', shallow: true, depth: 1, noTags: true, honorRefspec: true],
                                    [$class: 'CheckoutOption', timeout: 20],
                                ],
                            ])
                            // Immutable, traceable tag: <branch>-<build#>-<app-sha8>.
                            // REBUILD-SAFETY: Jenkins home is an ephemeral PVC, so
                            // BUILD_NUMBER resets to 1 on a rebuild — <branch>-<build#>
                            // alone re-mints tags that already exist in the persistent
                            // ghcr from a prior incarnation and mutably overwrites them.
                            // The SHA suffix makes the tag globally unique. (Set HERE,
                            // not in environment{} — see the note on that directive.)
                            def appSha = scmVars?.GIT_COMMIT?.trim()
                            if (appSha) {
                                env.IMAGE_TAG = "${cfg.gitBranch}-${env.BUILD_NUMBER}-${appSha.take(8)}"
                            } else {
                                env.IMAGE_TAG = "${cfg.gitBranch}-${env.BUILD_NUMBER}"
                                echo "WARNING: checkout returned no GIT_COMMIT - tag ${env.IMAGE_TAG} is NOT rebuild-safe"
                            }
                            env.IMAGE = "${env.REGISTRY}/${cfg.serviceName}:${env.IMAGE_TAG}"
                            echo "Image tag (rebuild-safe): ${env.IMAGE_TAG}"
                        }
                    }
                }
            }

            stage('Patch App Source') {
                // Gateway-only build-time patch, expressed as a when-gated stage
                // (skipped-stage visibility in Pipeline Graph View) instead of an
                // `if` buried in a script {} block. SINGLE SOURCE OF TRUTH: the
                // shared resources/patch-app-source.sh converts the gateway from
                // MySQL to PostgreSQL + a NoOp cache; ALL FOUR engines run this
                // same script. libraryResource materialises it from this shared
                // library into the app source cwd.
                when {
                    expression { cfg.serviceName == 'gateway' }
                }
                steps {
                    dir('microservices-src') {
                        writeFile file: '.patch-app-source.sh', text: libraryResource('patch-app-source.sh')
                        sh "bash .patch-app-source.sh '${cfg.serviceName}' ."
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

            // The three scanners are independent read-only reporters (separate
            // sidecar containers, disjoint outputs: semgrep/codeql write under
            // microservices-src/, trivy clones gitops-config-src at the workspace
            // root) — so they run as declarative parallel branches and CodeQL
            // (the long pole) no longer serialises Semgrep + Trivy behind it.
            // No failFast: scans are non-blocking by design (docs/601) — every
            // branch finishes and uploads its SARIF regardless of the others.
            // The Tekton port keeps these three sequential on purpose: its tasks
            // share one RWO PVC workspace; this single multi-container pod shares
            // the workspace natively, so Jenkins can parallelise where Tekton
            // cannot. Stage bodies live in vars/ custom steps (Declarative-first
            // rule, docs/403): the shell stays declarative, logic stays in the
            // library.
            stage('Static Analysis') {
                parallel {
                    stage('Semgrep SAST') {
                        steps {
                            microservicesSemgrepScan(repoUrl: cfg.gitRepoUrl, repoBranch: cfg.gitBranch)
                        }
                    }
                    stage('CodeQL Analysis') {
                        steps {
                            microservicesCodeqlScan(repoUrl: cfg.gitRepoUrl, repoBranch: cfg.gitBranch)
                        }
                    }
                    stage('Trivy IaC Scan') {
                        steps {
                            microservicesTrivyIacScan(envName: cfg.envName)
                        }
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

            stage('GitOps Update') {
                // The cross-engine deploy phase (docs/502), named identically in
                // all four engines' docs and runbooks: bump the image tag in the
                // gitops repo, push, then argocd sync + wait. This engine deploys
                // VIA ArgoCD — the GitOps update IS the deploy — so the phase is
                // a first-class Declarative stage here (it used to be a Scripted
                // stage() nested inside the step; hoisted for purity, docs/403 §7.6).
                steps {
                    microservicesDeploy(
                        serviceName: cfg.serviceName,
                        envName: cfg.envName,
                        tag: env.IMAGE_TAG
                    )
                }
            }

            stage('OTel Self-Heal') {
                // Heal the OTel auto-instrumentation injection race: the operator's
                // pod-mutation webhook is failurePolicy: Ignore, so a pod admitted
                // before the Instrumentation CR was ready starts WITHOUT the Java
                // agent (dashboards look empty). Its own stage so the check — and
                // any rollout restart it triggers — is visible in the build UI.
                steps {
                    microservicesOtelSelfHeal(
                        serviceName: cfg.serviceName,
                        namespace: cfg.targetNamespace
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
                    // k6JobName is resolved before pipeline {} (library-call time):
                    // 'develop' deploys to the microservices-develop namespace, so it
                    // hands off to 'microservices-k6-smoke-develop' (the seed generates
                    // one k6 job per environment). Pass TARGET_NAMESPACE/ENV_NAME
                    // explicitly rather than relying on the k6 job's parameter
                    // defaults: Jenkins does NOT apply a declarative job's default
                    // param values on its FIRST build after the seed (re)defines it,
                    // so a default-only trigger sent namespace="null" (-> gateway.null
                    // .svc, 100% request failures). Explicit params are robust on
                    // first build, re-seeds and manual runs alike.
                    echo "Triggering integration k6 smoke test: ${k6JobName} (env=${cfg.envName}, ns=${cfg.targetNamespace})..."
                    build job: k6JobName, wait: true, parameters: [
                        string(name: 'TARGET_NAMESPACE', value: cfg.targetNamespace),
                        string(name: 'ENV_NAME', value: cfg.envName)
                    ]
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

/**
 * MicroservicesK6SmokePipeline(targetNamespace: '<ns>', envName: 'stable'|'develop',
 *                           genaiEnabled: true|false, profile: '<profile>',
 *                           vus: '<n>', iterations: '<n>', ...)
 *
 * Declarative shared-library wrapper for the k6 traffic pipeline. The seed job
 * (jenkins/pipelines/seed/seed_jobs.groovy) calls this with the per-environment
 * defaults; the `parameters {}` block below turns those into a "Build with
 * Parameters" form so any run can be re-shaped on the fly (profile, VUs,
 * duration, ramping stages, arrival rate, thresholds, request flows) without
 * editing code. Every knob maps onto the K6SIM_* contract that
 * jenkins/pipelines/k6/microservices-smoke.js reads. See
 * docs/302-K6_LOAD_TESTING.md.
 *
 * Note: the argument map is named `cfg` (not `params`) on purpose — inside a
 * declarative pipeline `params` is the build-parameters object defined below.
 */
def call(Map cfg) {
    def defaultProfile = cfg.profile ?: 'smoke'
    def allProfiles = ['smoke', 'load', 'stress', 'soak', 'spike', 'breakpoint']
    // Put the seed-provided default first so it is the choice param's default.
    def profileChoices = [defaultProfile] + (allProfiles - defaultProfile)

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

        parameters {
            // ---- Target -----------------------------------------------------
            string(name: 'TARGET_NAMESPACE', defaultValue: cfg.targetNamespace ?: 'microservices',
                   description: 'In-cluster namespace whose Services receive the traffic.')
            string(name: 'ENV_NAME', defaultValue: cfg.envName ?: 'stable',
                   description: 'deployment.environment OTel label (stable | develop). Scopes the Grafana dashboard.')
            string(name: 'TARGET_URL', defaultValue: cfg.targetUrl ?: '',
                   description: 'Optional external base URL (e.g. https://microservices.<domain>). Empty → in-cluster Service DNS in TARGET_NAMESPACE.')
            // ---- Workload ---------------------------------------------------
            choice(name: 'PROFILE', choices: profileChoices,
                   description: 'smoke (telemetry only) · load · stress · soak (long) · spike · breakpoint (ramps until it breaks).')
            string(name: 'VUS', defaultValue: (cfg.vus ?: '') as String,
                   description: 'Virtual users / pre-allocated VUs. Empty → the profile default.')
            string(name: 'ITERATIONS', defaultValue: (cfg.iterations ?: '') as String,
                   description: 'Shared iterations (smoke profile only). Empty → profile default (12).')
            string(name: 'DURATION', defaultValue: (cfg.duration ?: '') as String,
                   description: 'Hold duration, e.g. 30s / 5m / 1h. Overrides the iteration budget.')
            string(name: 'STAGES', defaultValue: (cfg.stages ?: '') as String,
                   description: 'Custom ramping stages "dur:target,..." e.g. 30s:10,2m:50,30s:0. Overrides the profile.')
            string(name: 'RPS', defaultValue: (cfg.rps ?: '') as String,
                   description: 'Constant arrival rate (requests/sec). Overrides the profile with a constant-arrival-rate executor.')
            string(name: 'SLEEP', defaultValue: (cfg.sleep ?: '') as String,
                   description: 'Think-time seconds between requests. Empty → 0.3.')
            string(name: 'SCENARIOS', defaultValue: (cfg.scenarios ?: '') as String,
                   description: 'Request flows: "all" or a comma list of gateway-ui,gateway-health,microservice-health,gateway-proxy.')
            // ---- Thresholds -------------------------------------------------
            string(name: 'P95_MS', defaultValue: (cfg.p95Ms ?: '') as String,
                   description: 'http_req_duration p(95) budget in ms. Empty → 3000.')
            string(name: 'ERROR_RATE', defaultValue: (cfg.errorRate ?: '') as String,
                   description: 'Max http_req_failed rate (0..1). Empty → 0.05.')
            booleanParam(name: 'DEBUG', defaultValue: (cfg.debug ?: false) as boolean,
                   description: 'Per-iteration console logging (trace ids, resolved config).')
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
            stage('Run k6 Traffic') {
                steps {
                    microservicesK6Smoke(
                        namespace:   params.TARGET_NAMESPACE,
                        envName:     params.ENV_NAME,
                        targetUrl:   params.TARGET_URL,
                        genaiEnabled: cfg.genaiEnabled,
                        profile:     params.PROFILE,
                        vus:         params.VUS,
                        iterations:  params.ITERATIONS,
                        duration:    params.DURATION,
                        stages:      params.STAGES,
                        rps:         params.RPS,
                        sleep:       params.SLEEP,
                        scenarios:   params.SCENARIOS,
                        p95Ms:       params.P95_MS,
                        errorRate:   params.ERROR_RATE,
                        debug:       params.DEBUG
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

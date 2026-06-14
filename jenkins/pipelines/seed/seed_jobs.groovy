/*
 * Job DSL script: pipelines-as-code for PetClinic.
 *
 * Reads services.yaml (this directory) and, for each service, creates one or
 * more pipeline jobs that all run jenkins/pipelines/Jenkinsfile.petclinic
 * (script-from-SCM, this repo) with per-job parameter defaults defined here.
 * Re-running this script (any "seed-jobs*" job, see
 * jenkins/casc/jcasc-seed-job.yaml) is idempotent: Job DSL reconciles
 * existing jobs to match this definition.
 *
 * JOB_FOLDER (passed in via the jobDsl step's additionalParameters, see
 * Jenkinsfile.seed) is derived from the calling seed job's own location and
 * selects WHICH set of jobs gets generated:
 *
 *   JOB_FOLDER == ''        - the ROOT "seed-jobs" job (tracks this repo's
 *                              JENKINS2026_REPO_BRANCH, normally "main").
 *                              Creates ONE job per service - the stable,
 *                              tested pipeline:
 *                                <name>  - builds PetClinic `branches.stable` (main) -> namespaces.stable.
 *                                          Jenkinsfile.petclinic + shared library come from
 *                                          JENKINS2026_REPO_BRANCH (main).
 *                              ...plus ONE extra job, not from services.yaml:
 *                                petclinic-k6-smoke  - runs a small k6 observability smoke test
 *                                                      against namespaces.stable. Jenkinsfile.petclinic-k6-smoke
 *                                                      + shared library come from JENKINS2026_REPO_BRANCH (main).
 *
 *   JOB_FOLDER == 'pac-dev'  - the "pac-dev/seed-jobs-dev" job (tracks this
 *                              repo's JENKINS2026_DEV_REPO_BRANCH, normally
 *                              "develop"). Creates ONE job per service inside
 *                              the pac-dev/ folder - the GitFlow "-develop"
 *                              track:
 *                                pac-dev/<name>-develop  - builds PetClinic `branches.develop` (main) -> namespaces.develop.
 *                                                          Jenkinsfile.petclinic + shared library come from
 *                                                          JENKINS2026_DEV_REPO_BRANCH (develop).
 *                              ...plus ONE extra job, not from services.yaml:
 *                                pac-dev/petclinic-k6-smoke-develop  - runs the same k6 smoke test against
 *                                                                      namespaces.develop. Jenkinsfile.petclinic-k6-smoke
 *                                                                      + shared library come from JENKINS2026_DEV_REPO_BRANCH (develop).
 *
 * The pac-dev/ folder is an isolated sandbox where devops/platform engineers
 * can change and improve seed_jobs.groovy itself, Jenkinsfile.petclinic, JCasC
 * or the shared library on the `develop` branch and see the resulting
 * "-develop" pipelines run end-to-end against their own namespace
 * (namespaces.develop / petclinic-develop) - without any of this affecting
 * the 9 stable <name> jobs at the root, which always run the tested
 * JENKINS2026_REPO_BRANCH/main definitions. It is kept out of the default
 * root view and, per the "platform-engineer" role in
 * jenkins/casc/jcasc-base.yaml, hidden from regular "developer" users - see
 * README.md "Pipelines-as-code dev sandbox".
 */

import org.yaml.snakeyaml.Yaml

def repoUrl       = System.getenv('JENKINS2026_REPO_URL')        ?: 'https://github.com/nubenetes/jenkins-2026.git'
def stableBranch  = System.getenv('JENKINS2026_REPO_BRANCH')     ?: 'main'
def devBranch     = System.getenv('JENKINS2026_DEV_REPO_BRANCH') ?: 'develop'
def platform      = System.getenv('JENKINS2026_PLATFORM')        ?: 'gke'

// genai-service (Spring AI) crashes on startup without a real OPENAI_API_KEY
// (see helm/petclinic/values-*.yaml) - until one is configured, its pipeline
// jobs are created disabled so they can't be triggered. Set
// petclinic.genaiServiceEnabled: true in config/config.yaml (or export
// JENKINS2026_GENAI_SERVICE_ENABLED=true), then re-run seed-jobs, once a real
// key is wired in.
def genaiServiceEnabled = (System.getenv('JENKINS2026_GENAI_SERVICE_ENABLED') ?: 'false').toBoolean()

// JOB_FOLDER is provided via additionalParameters by Jenkinsfile.seed; empty
// string (the root seed-jobs job) if absent so this script also works when
// run manually/outside that pipeline.
def jobFolder = binding.hasVariable('JOB_FOLDER') ? (JOB_FOLDER as String) : ''

// Branch this seed job (and therefore this script's own definition of the
// jobs below) was checked out from - used only for the folder/listView
// descriptions. The per-job Jenkinsfile/shared-library source branch is
// `flavour.pipelineRepoBranch` below, which differs per flavour.
def repoBranch = jobFolder ? devBranch : stableBranch

def yamlText = readFileFromWorkspace('jenkins/pipelines/seed/services.yaml')
def registry = new Yaml().load(yamlText)

def namespaces  = registry.namespaces
def gitFlowRefs = registry.branches

// pipeline "flavour" generated per service. `pipelineRepoBranch` is the
// jenkins-2026 branch that Jenkinsfile.petclinic + the shared library are
// checked out from for that job (see header comment); `branchKey` selects
// which of services.yaml's top-level `branches` (or a per-service `branches`
// override, e.g. petclinic-angular's `master`) to build:
//  - root (JOB_FOLDER==''): stable -> tracks branches.stable (main) w/ Jenkinsfile from stableBranch
//  - pac-dev (JOB_FOLDER=='pac-dev'): -develop -> tracks branches.develop (main) w/ Jenkinsfile from devBranch
def flavours = jobFolder
  ? [
      [suffix: '-develop', branchKey: 'develop', namespaceKey: 'develop', envName: 'develop', pipelineRepoBranch: devBranch],
    ]
  : [
      [suffix: '', branchKey: 'stable', namespaceKey: 'stable', envName: 'stable', pipelineRepoBranch: stableBranch],
    ]

if (jobFolder) {
  folder(jobFolder) {
    description("Pipelines-as-code DEV sandbox - jobs below are (re)generated from this repo's '${repoBranch}' branch by pac-dev/seed-jobs-dev. Visible only to the platform-engineer role (see jenkins/casc/jcasc-base.yaml). Managed by jenkins-2026 seed-jobs - do not edit manually.")
  }
}

registry.services.each { svc ->
  flavours.each { flavour ->
    def jobName = jobFolder ? "${jobFolder}/${svc.name}${flavour.suffix}" : "${svc.name}${flavour.suffix}"
    def branch  = svc.branches?.get(flavour.branchKey) ?: gitFlowRefs[flavour.branchKey]

    def disabledReason = (svc.name == 'genai-service' && !genaiServiceEnabled)
      ? " DISABLED: requires a real OPENAI_API_KEY (see config/config.yaml petclinic.genaiServiceEnabled) - currently only a startup placeholder is configured."
      : ""

    pipelineJob(jobName) {
      description("PetClinic '${svc.name}' (${flavour.envName}) - builds '${branch}' from ${svc.repoUrl} and deploys to namespace '${namespaces[flavour.namespaceKey]}'. Jenkinsfile.petclinic + shared library from jenkins-2026 '${flavour.pipelineRepoBranch}'. Managed by jenkins-2026 seed-jobs - do not edit manually.${disabledReason}")
      keepDependencies(false)
      disabled(svc.name == 'genai-service' && !genaiServiceEnabled)
      logRotator {
        numToKeep(20)
      }

      definition {
        cpsScm {
          scm {
            git {
              remote {
                url(repoUrl)
              }
              branches("*/${flavour.pipelineRepoBranch}")
            }
          }
          scriptPath('jenkins/pipelines/Jenkinsfile.petclinic')
          lightweight(true)
        }
      }

      parameters {
        stringParam('SERVICE_NAME', svc.name, 'PetClinic service name')
        stringParam('SERVICE_TYPE', svc.type, 'Build flavour: java|angular')
        stringParam('MODULE_PATH', svc.module ?: '', 'Maven module subdirectory (java services only)')
        stringParam('GIT_REPO_URL', svc.repoUrl, 'Source repository to build')
        stringParam('GIT_BRANCH', branch, "GitFlow branch for the '${flavour.envName}' pipeline")
        stringParam('TARGET_NAMESPACE', namespaces[flavour.namespaceKey], 'Kubernetes namespace to deploy into')
        stringParam('ENV_NAME', flavour.envName, 'helm/petclinic values overlay (values-<ENV_NAME>.yaml)')
        stringParam('PORT', "${svc.port}", 'Container port used for the smoke test')
        stringParam('HEALTH_PATH', svc.healthPath ?: '/actuator/health', 'HTTP path used for the smoke test')
        stringParam('PLATFORM', platform, 'Target platform (gke|eks|aks|openshift) - selects the deploy overlay')
      }

      // Deliberately no pipelineTriggers/pollSCM: with 18 jobs sharing two
      // Helm releases, an SCM-triggered "rebuild everything" on every
      // jenkins-2026/PetClinic commit floods the build queue and burns GKE
      // node hours. Jobs are manually triggered (buildButton in the
      // "petclinic"/"pac-dev/petclinic-develop" views).
    }
  }
}

// PetClinic Grafana observability smoke test (k6) - one job per flavour, not
// driven by services.yaml since it isn't a per-service build/deploy pipeline:
// it just sends a small amount of synthetic traffic through the PetClinic
// Services that the jobs above just deployed, so Grafana Cloud has fresh
// traces/metrics/logs to correlate. See
// jenkins/pipelines/Jenkinsfile.petclinic-k6-smoke and
// jenkins/pipelines/k6/petclinic-smoke.js.
flavours.each { flavour ->
  def jobName = jobFolder ? "${jobFolder}/petclinic-k6-smoke${flavour.suffix}" : "petclinic-k6-smoke${flavour.suffix}"

  pipelineJob(jobName) {
    description("PetClinic Grafana observability smoke test (k6, ${flavour.envName}) - sends a small amount of synthetic traffic (a few VUs/iterations, NOT a load test) through every PetClinic Service in namespace '${namespaces[flavour.namespaceKey]}', with W3C trace context propagation, to exercise Grafana Cloud traces/metrics/logs correlation. Jenkinsfile.petclinic-k6-smoke + shared library from jenkins-2026 '${flavour.pipelineRepoBranch}'. Managed by jenkins-2026 seed-jobs - do not edit manually.")
    keepDependencies(false)
    logRotator {
      numToKeep(20)
    }

    definition {
      cpsScm {
        scm {
          git {
            remote {
              url(repoUrl)
            }
            branches("*/${flavour.pipelineRepoBranch}")
          }
        }
        scriptPath('jenkins/pipelines/Jenkinsfile.petclinic-k6-smoke')
        lightweight(true)
      }
    }

    parameters {
      stringParam('TARGET_NAMESPACE', namespaces[flavour.namespaceKey], 'Kubernetes namespace whose PetClinic Services to test')
      stringParam('ENV_NAME', flavour.envName, 'deployment.environment resource attribute applied to k6 OTel metrics, matching helm/petclinic/templates/instrumentation.yaml')
      booleanParam('GENAI_SERVICE_ENABLED', genaiServiceEnabled, 'Whether to also probe genai-service (see config/config.yaml petclinic.genaiServiceEnabled)')
      stringParam('K6_VUS', '4', 'Number of k6 virtual users')
      stringParam('K6_ITERATIONS', '12', 'Total k6 iterations (shared across K6_VUS)')
    }

    // Deliberately no pipelineTriggers/pollSCM - run manually (buildButton in
    // the "petclinic"/"pac-dev/petclinic-develop" views), e.g. after one or
    // more of the deploy pipelines above, same as those jobs.
  }
}

// Convenience view grouping all generated PetClinic jobs together.
if (!jobFolder) {
  listView('petclinic') {
    description('All stable PetClinic pipelines-as-code jobs, generated from services.yaml, plus the k6 observability smoke test. The GitFlow "-develop" track lives in the pac-dev/ sandbox (see petclinic-develop view).')
    jobs {
      registry.services.each { svc ->
        name(svc.name)
      }
      name('petclinic-k6-smoke')
    }
    columns {
      status()
      weather()
      name()
      lastSuccess()
      lastFailure()
      lastDuration()
      buildButton()
    }
  }

  listView('petclinic-develop') {
    description("PetClinic '-develop' pipelines-as-code dev sandbox jobs (from pac-dev/ folder), generated from services.yaml on the '${devBranch}' branch. Restricted to platform-engineers.")
    recurse(true)
    jobs {
      registry.services.each { svc ->
        name("pac-dev/${svc.name}-develop")
      }
      name('pac-dev/petclinic-k6-smoke-develop')
      name("pac-dev/seed-jobs-dev")
    }
    columns {
      status()
      weather()
      name()
      lastSuccess()
      lastFailure()
      lastDuration()
      buildButton()
    }
  }
}

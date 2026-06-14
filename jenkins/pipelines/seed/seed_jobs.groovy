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
 *                              Creates the GitFlow pair per service:
 *                                <name>          - builds PetClinic `branches.stable`  (main) -> namespaces.stable.
 *                                                   Jenkinsfile.petclinic + shared library come from
 *                                                   JENKINS2026_REPO_BRANCH (main).
 *                                <name>-develop  - builds PetClinic `branches.develop` (main) -> namespaces.develop.
 *                                                   Jenkinsfile.petclinic + shared library come from
 *                                                   JENKINS2026_DEV_REPO_BRANCH (develop) - so pipeline-as-code
 *                                                   changes land here first, without affecting <name>.
 *
 *   JOB_FOLDER == 'pac-dev'  - the "pac-dev/seed-jobs-dev" job (tracks this
 *                              repo's JENKINS2026_DEV_REPO_BRANCH, normally
 *                              "develop"). Creates ONE job per service inside
 *                              the pac-dev/ folder:
 *                                pac-dev/<name>  - builds PetClinic `branches.develop` (main) -> namespaces.pacDev.
 *                                                   Jenkinsfile.petclinic + shared library also come from
 *                                                   JENKINS2026_DEV_REPO_BRANCH (develop).
 *
 * The pac-dev/ folder is a sandbox for devops/platform engineers to iterate
 * on this repo's pipelines-as-code (this file, seed_jobs.groovy itself) on
 * the `develop` branch without affecting the root seed-jobs definitions
 * above - see README.md "Pipelines-as-code dev sandbox" and the
 * "platform-engineer" role in jenkins/casc/jcasc-base.yaml, which is the only
 * role with Job/Read on pac-dev/*. Note pac-dev/<name> and <name>-develop now
 * both run Jenkinsfile.petclinic from JENKINS2026_DEV_REPO_BRANCH (develop) -
 * they differ only in deploy namespace/visibility.
 */

import org.yaml.snakeyaml.Yaml

def repoUrl       = System.getenv('JENKINS2026_REPO_URL')        ?: 'https://github.com/nubenetes/jenkins-2026.git'
def stableBranch  = System.getenv('JENKINS2026_REPO_BRANCH')     ?: 'main'
def devBranch     = System.getenv('JENKINS2026_DEV_REPO_BRANCH') ?: 'develop'
def platform      = System.getenv('JENKINS2026_PLATFORM')        ?: 'gke'

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

// pipeline "flavours" generated per service. `pipelineRepoBranch` is the
// jenkins-2026 branch that Jenkinsfile.petclinic + the shared library are
// checked out from for that job (see header comment); `branchKey` selects
// which of services.yaml's top-level `branches` (or a per-service `branches`
// override, e.g. petclinic-angular's `master`) to build:
//  - root (JOB_FOLDER==''): stable -> tracks branches.stable (main) w/ Jenkinsfile from stableBranch,
//                           *-develop -> tracks branches.develop (main) w/ Jenkinsfile from devBranch
//  - pac-dev (JOB_FOLDER=='pac-dev'): single flavour tracking branches.develop (main) w/ Jenkinsfile from devBranch
def flavours = jobFolder
  ? [
      [suffix: '', branchKey: 'develop', namespaceKey: 'pacDev', envName: 'pac-dev', pipelineRepoBranch: devBranch],
    ]
  : [
      [suffix: '',         branchKey: 'stable',  namespaceKey: 'stable',  envName: 'stable',  pipelineRepoBranch: stableBranch],
      [suffix: '-develop', branchKey: 'develop', namespaceKey: 'develop', envName: 'develop', pipelineRepoBranch: devBranch],
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

    pipelineJob(jobName) {
      description("PetClinic '${svc.name}' (${flavour.envName}) - builds '${branch}' from ${svc.repoUrl} and deploys to namespace '${namespaces[flavour.namespaceKey]}'. Jenkinsfile.petclinic + shared library from jenkins-2026 '${flavour.pipelineRepoBranch}'. Managed by jenkins-2026 seed-jobs - do not edit manually.")
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
      // "petclinic"/"petclinic-pac-dev" views).
    }
  }
}

// Convenience view grouping all generated PetClinic jobs together.
if (jobFolder) {
  listView("${jobFolder}/petclinic-pac-dev") {
    description("PetClinic pipelines-as-code DEV sandbox jobs, generated from services.yaml on the '${repoBranch}' branch.")
    jobs {
      registry.services.each { svc ->
        name("${jobFolder}/${svc.name}")
      }
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
} else {
  listView('petclinic') {
    description('All PetClinic pipelines-as-code jobs (stable + develop), generated from services.yaml')
    jobs {
      registry.services.each { svc ->
        name(svc.name)
        name("${svc.name}-develop")
      }
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

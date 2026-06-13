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
 *                                <name>          - tracks `branches.stable`  (master)  -> namespaces.stable
 *                                <name>-develop  - tracks `branches.develop` (develop) -> namespaces.develop
 *
 *   JOB_FOLDER == 'pac-dev'  - the "pac-dev/seed-jobs-dev" job (tracks this
 *                              repo's JENKINS2026_DEV_REPO_BRANCH, normally
 *                              "develop"). Creates ONE job per service inside
 *                              the pac-dev/ folder:
 *                                pac-dev/<name>  - tracks `branches.develop` (develop) -> namespaces.pacDev
 *
 * The pac-dev/ folder is a sandbox for devops/platform engineers to iterate
 * on this repo's pipelines-as-code (this file, Jenkinsfile.petclinic, the
 * shared library) on the `develop` branch without affecting the stable/
 * develop jobs above - see README.md "Pipelines-as-code dev sandbox" and the
 * "platform-engineer" role in jenkins/casc/jcasc-base.yaml, which is the only
 * role with Job/Read on pac-dev/*.
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

// The root seed-jobs job sources generated Jenkinsfiles/shared-library from
// JENKINS2026_REPO_BRANCH (main); the pac-dev seed job sources them from
// JENKINS2026_DEV_REPO_BRANCH (develop) - this is what lets pipeline-as-code
// changes on `develop` be tested via pac-dev/* before merging to `main`.
def repoBranch = jobFolder ? devBranch : stableBranch

def yamlText = readFileFromWorkspace('jenkins/pipelines/seed/services.yaml')
def registry = new Yaml().load(yamlText)

def namespaces  = registry.namespaces
def gitFlowRefs = registry.branches

// pipeline "flavours" generated per service:
//  - root (JOB_FOLDER==''): stable -> tracks master, *-develop -> tracks develop
//  - pac-dev (JOB_FOLDER=='pac-dev'): single flavour tracking develop
def flavours = jobFolder
  ? [
      [suffix: '', branch: gitFlowRefs.develop, namespaceKey: 'pacDev', envName: 'pac-dev'],
    ]
  : [
      [suffix: '',         branch: gitFlowRefs.stable,  namespaceKey: 'stable',  envName: 'stable'],
      [suffix: '-develop', branch: gitFlowRefs.develop, namespaceKey: 'develop', envName: 'develop'],
    ]

if (jobFolder) {
  folder(jobFolder) {
    description("Pipelines-as-code DEV sandbox - jobs below are (re)generated from this repo's '${repoBranch}' branch by pac-dev/seed-jobs-dev. Visible only to the platform-engineer role (see jenkins/casc/jcasc-base.yaml). Managed by jenkins-2026 seed-jobs - do not edit manually.")
  }
}

registry.services.each { svc ->
  flavours.each { flavour ->
    def jobName = jobFolder ? "${jobFolder}/${svc.name}${flavour.suffix}" : "${svc.name}${flavour.suffix}"

    pipelineJob(jobName) {
      description("PetClinic '${svc.name}' (${flavour.envName}) - builds '${flavour.branch}' from ${svc.repoUrl} and deploys to namespace '${namespaces[flavour.namespaceKey]}'. Managed by jenkins-2026 seed-jobs - do not edit manually.")
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
              branches("*/${repoBranch}")
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
        stringParam('GIT_BRANCH', flavour.branch, "GitFlow branch for the '${flavour.envName}' pipeline")
        stringParam('TARGET_NAMESPACE', namespaces[flavour.namespaceKey], 'Kubernetes namespace to deploy into')
        stringParam('ENV_NAME', flavour.envName, 'helm/petclinic values overlay (values-<ENV_NAME>.yaml)')
        stringParam('PORT', "${svc.port}", 'Container port used for the smoke test')
        stringParam('HEALTH_PATH', svc.healthPath ?: '/actuator/health', 'HTTP path used for the smoke test')
        stringParam('PLATFORM', platform, 'Target platform (gke|eks|aks|openshift) - selects the deploy overlay')
      }

      properties {
        pipelineTriggers {
          triggers {
            // Poll every 5 minutes for new commits on the tracked branch -
            // works out of the box without configuring a webhook. pollSCM
            // is the Describable symbol for hudson.triggers.SCMTrigger.
            pollSCM {
              scmpoll_spec('H/5 * * * *')
            }
          }
        }
      }
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

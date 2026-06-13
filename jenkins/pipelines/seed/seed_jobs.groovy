/*
 * Job DSL script: pipelines-as-code for PetClinic.
 *
 * Reads services.yaml (this directory) and, for each service, creates TWO
 * pipeline jobs implementing the GitFlow model requested for this PoC:
 *
 *   <name>          - tracks the STABLE branch (master)  -> namespaces.stable
 *   <name>-develop  - tracks the DEVELOP branch (develop) -> namespaces.develop
 *
 * Both jobs run jenkins/pipelines/Jenkinsfile.petclinic (script-from-SCM,
 * this repo) with per-job parameter defaults defined here. Re-running this
 * script (the "seed-jobs" job, see jenkins/casc/jcasc-seed-job.yaml) is
 * idempotent: Job DSL reconciles existing jobs to match this definition.
 */

import org.yaml.snakeyaml.Yaml

def repoUrl    = System.getenv('JENKINS2026_REPO_URL')    ?: 'https://github.com/nubenetes/jenkins-2026.git'
def repoBranch = System.getenv('JENKINS2026_REPO_BRANCH') ?: 'main'
def platform   = System.getenv('JENKINS2026_PLATFORM')    ?: 'gke'

def yamlText = readFileFromWorkspace('jenkins/pipelines/seed/services.yaml')
def registry = new Yaml().load(yamlText)

def namespaces  = registry.namespaces
def gitFlowRefs = registry.branches

// pipeline "flavours": stable -> tracks master, *-develop -> tracks develop
def flavours = [
  [suffix: '',         branch: gitFlowRefs.stable,  namespaceKey: 'stable',  envName: 'stable'],
  [suffix: '-develop', branch: gitFlowRefs.develop, namespaceKey: 'develop', envName: 'develop'],
]

registry.services.each { svc ->
  flavours.each { flavour ->
    def jobName = "${svc.name}${flavour.suffix}"

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
            // works out of the box without configuring a webhook.
            scm {
              scmpoll_spec('H/5 * * * *')
            }
          }
        }
      }
    }
  }
}

// Convenience view grouping all PetClinic jobs together.
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

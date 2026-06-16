/*
 * Job DSL script: pipelines-as-code for Microservices.
 *
 * Reads services.yaml (this directory) and, for each service, creates one or
 * more pipeline jobs that call the declarative shared library MicroservicesPipeline
 * or MicroservicesK6SmokePipeline.
 */

import org.yaml.snakeyaml.Yaml

def repoUrl       = System.getenv('JENKINS2026_REPO_URL')        ?: 'https://github.com/nubenetes/jenkins-2026.git'
def stableBranch  = System.getenv('JENKINS2026_REPO_BRANCH')     ?: 'main'
def devBranch     = System.getenv('JENKINS2026_DEV_REPO_BRANCH') ?: 'develop'
def platform      = System.getenv('JENKINS2026_PLATFORM')        ?: 'gke'

def genaiServiceEnabled = (System.getenv('JENKINS2026_GENAI_SERVICE_ENABLED') ?: 'false').toBoolean()
def jobFolder = binding.hasVariable('JOB_FOLDER') ? (JOB_FOLDER as String) : ''
def repoBranch = jobFolder ? devBranch : stableBranch

def yamlText = readFileFromWorkspace('jenkins/pipelines/seed/services.yaml')
def registry = new Yaml().load(yamlText)

def namespaces  = registry.namespaces
def gitFlowRefs = registry.branches

def flavours = jobFolder
  ? [
      [suffix: '-develop', branchKey: 'develop', namespaceKey: 'develop', envName: 'develop', pipelineRepoBranch: devBranch],
    ]
  : [
      [suffix: '', branchKey: 'stable', namespaceKey: 'stable', envName: 'stable', pipelineRepoBranch: stableBranch],
    ]

if (jobFolder) {
  folder(jobFolder) {
    description("Pipelines-as-code DEV sandbox - jobs below are (re)generated from this repo's '${repoBranch}' branch.")
  }
}

registry.services.each { svc ->
  flavours.each { flavour ->
    def jobName = jobFolder ? "${jobFolder}/${svc.name}${flavour.suffix}" : "${svc.name}${flavour.suffix}"
    def branch  = svc.branches?.get(flavour.branchKey) ?: gitFlowRefs[flavour.branchKey]

    pipelineJob(jobName) {
      description("Microservices '${svc.name}' (${flavour.envName}) - builds '${branch}' and deploys to namespace '${namespaces[flavour.namespaceKey]}'.")
      keepDependencies(false)
      disabled(svc.name == 'genai-service' && !genaiServiceEnabled)
      logRotator { numToKeep(20) }

      definition {
        cps {
          script("""
@Library("microservices-shared-library@${flavour.pipelineRepoBranch}") _
MicroservicesPipeline(
    serviceName: '${svc.name}',
    serviceType: '${svc.type}',
    modulePath: '${svc.module ?: ""}',
    gitRepoUrl: '${svc.repoUrl}',
    gitBranch: '${branch}',
    targetNamespace: '${namespaces[flavour.namespaceKey]}',
    envName: '${flavour.envName}',
    port: '${svc.port}',
    healthPath: '${svc.healthPath ?: "/actuator/health"}',
    platform: '${platform}'
)
""".stripIndent())
          sandbox(true)
        }
      }
    }
  }
}

flavours.each { flavour ->
  def jobName = jobFolder ? "${jobFolder}/microservices-k6-smoke${flavour.suffix}" : "microservices-k6-smoke${flavour.suffix}"

  pipelineJob(jobName) {
    description("Microservices Grafana observability smoke test (k6, ${flavour.envName}).")
    keepDependencies(false)
    logRotator { numToKeep(20) }

    definition {
      cps {
        script("""
@Library("microservices-shared-library@${flavour.pipelineRepoBranch}") _
MicroservicesK6SmokePipeline(
    targetNamespace: '${namespaces[flavour.namespaceKey]}',
    envName: '${flavour.envName}',
    genaiEnabled: ${genaiServiceEnabled},
    vus: '4',
    iterations: '12'
)
""".stripIndent())
        sandbox(true)
      }
    }
  }
}

if (!jobFolder) {
  listView('microservices') {
    jobs {
      registry.services.each { name(it.name) }
      name('microservices-k6-smoke')
    }
    columns { status(); weather(); name(); lastSuccess(); lastFailure(); lastDuration(); buildButton() }
  }
} else {
  listView('microservices-develop') {
    recurse(true)
    jobs {
      registry.services.each { name("pac-dev/${it.name}-develop") }
      name('pac-dev/microservices-k6-smoke-develop')
      name("pac-dev/seed-jobs-dev")
    }
    columns { status(); weather(); name(); lastSuccess(); lastFailure(); lastDuration(); buildButton() }
  }
}

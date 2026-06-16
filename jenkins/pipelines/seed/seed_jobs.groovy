/*
 * Job DSL script: pipelines-as-code for Microservices.
 *
 * Reads services.yaml (this directory) and, for each service, creates
 * pipeline jobs that call the declarative shared library MicroservicesPipeline
 * or MicroservicesK6SmokePipeline.
 *
 * It dynamically configures the pipelines (namespaces, environment, branch tracking)
 * based on the active branch of the infra repo (jenkins-2026) currently deployed.
 *
 * Single-view model (since v0.5): all jobs live at the root in the 'microservices'
 * ListView. The old 'pac-dev' folder and 'microservices-develop' view are pruned
 * automatically on every seed run (see "Prune legacy resources" block below).
 */

import org.yaml.snakeyaml.Yaml

def repoUrl       = System.getenv('JENKINS2026_REPO_URL')        ?: 'https://github.com/nubenetes/jenkins-2026.git'
def infraBranch   = System.getenv('JENKINS2026_REPO_BRANCH')     ?: 'main'
def platform      = System.getenv('JENKINS2026_PLATFORM')        ?: 'gke'
def genaiServiceEnabled = (System.getenv('JENKINS2026_GENAI_SERVICE_ENABLED') ?: 'false').toBoolean()

def yamlText = readFileFromWorkspace('jenkins/pipelines/seed/services.yaml')
def registry = new Yaml().load(yamlText)

def namespaces  = registry.namespaces
def gitFlowRefs = registry.branches

// Determine configuration dynamically. The legacy 'develop' track is pruned.
def envName = 'stable'
def targetNamespace = namespaces.stable
def branchKey = 'stable'
def pipelineRepoBranch = infraBranch

// ---------------------------------------------------------------------------
// Prune legacy resources from the old dual-branch pipeline model (pre-v0.5).
// The previous model placed develop variants inside a 'pac-dev' Folder and
// exposed them via a 'microservices-develop' ListView.  Both are now obsolete.
// Deleting them here is idempotent - no-ops if they are already absent.
// ---------------------------------------------------------------------------
def jenkinsInst = jenkins.model.Jenkins.get()

def legacyFolder = jenkinsInst.getItem('pac-dev')
if (legacyFolder) {
    legacyFolder.delete()
    println "[seed] Pruned legacy folder: pac-dev"
}

def legacyView = jenkinsInst.getView('microservices-develop')
if (legacyView) {
    jenkinsInst.deleteView(legacyView)
    println "[seed] Pruned legacy view: microservices-develop"
}

registry.services.each { svc ->
  def jobName = svc.name
  def branch  = svc.branches?.get(branchKey) ?: gitFlowRefs[branchKey]

  pipelineJob(jobName) {
    description("Microservices '${svc.name}' (${envName}) - builds '${branch}' and deploys to namespace '${targetNamespace}'. Tracked via branch '${infraBranch}' of jenkins-2026.")
    keepDependencies(false)
    disabled(svc.name == 'genai-service' && !genaiServiceEnabled)
    logRotator { numToKeep(20) }

    definition {
      cps {
        script("""
@Library("microservices-shared-library@${pipelineRepoBranch}") _
MicroservicesPipeline(
    serviceName: '${svc.name}',
    serviceType: '${svc.type}',
    modulePath: '${svc.module ?: ""}',
    gitRepoUrl: '${svc.repoUrl}',
    gitBranch: '${branch}',
    targetNamespace: '${targetNamespace}',
    envName: '${envName}',
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

// Generate the k6 smoke test job at the root
pipelineJob('microservices-k6-smoke') {
  description("Microservices Grafana observability smoke test (k6, ${envName}). Tracked via branch '${infraBranch}' of jenkins-2026.")
  keepDependencies(false)
  logRotator { numToKeep(20) }

  definition {
    cps {
      script("""
@Library("microservices-shared-library@${pipelineRepoBranch}") _
MicroservicesK6SmokePipeline(
    targetNamespace: '${targetNamespace}',
    envName: '${envName}',
    genaiEnabled: ${genaiServiceEnabled},
    vus: '4',
    iterations: '12'
)
""".stripIndent())
      sandbox(true)
    }
  }
}

// Single 'microservices' ListView at the root - all service jobs + k6 smoke.
listView('microservices') {
  jobs {
    registry.services.each { name(it.name) }
    name('microservices-k6-smoke')
  }
  columns { status(); weather(); name(); lastSuccess(); lastFailure(); lastDuration(); buildButton() }
}

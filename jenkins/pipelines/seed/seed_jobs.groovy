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
 * Default (develop track OFF): all jobs live at the root in the 'microservices'
 * ListView. When the optional develop tier is enabled
 * (JENKINS2026_DEVELOP_TRACK_ENABLED), parallel '<svc>-develop' jobs and a
 * 'microservices-develop' ListView are generated alongside them. The legacy
 * pre-v0.5 'pac-dev' Folder is always pruned (see "Prune legacy resources").
 */

import org.yaml.snakeyaml.Yaml

def repoUrl       = System.getenv('JENKINS2026_REPO_URL')        ?: 'https://github.com/nubenetes/jenkins-2026.git'
def infraBranch   = System.getenv('JENKINS2026_REPO_BRANCH')     ?: 'main'
def platform      = System.getenv('JENKINS2026_PLATFORM')        ?: 'gke'
def genaiServiceEnabled = (System.getenv('JENKINS2026_GENAI_SERVICE_ENABLED') ?: 'false').toBoolean()
def developTrackEnabled = (System.getenv('JENKINS2026_DEVELOP_TRACK_ENABLED') ?: 'false').toBoolean()

def yamlText = readFileFromWorkspace('jenkins/pipelines/seed/services.yaml')
def registry = new Yaml().load(yamlText)

def namespaces  = registry.namespaces
def gitFlowRefs = registry.branches

// Shared library version follows whatever infra branch is deployed (single
// controller), for both tiers.
def pipelineRepoBranch = infraBranch

// Environments to generate jobs for. 'stable' always lives at the root with bare
// job names. The optional 'develop' tier (off by default - it roughly doubles the
// microservices footprint) adds parallel '<svc>-develop' jobs in its own ListView,
// deploying to the develop namespace. The app source branch is resolved per
// service from services.yaml 'branches' (still 'main' upstream); only the deploy
// namespace + gitops values differ.
def environments = [
  [name: 'stable', namespace: namespaces.stable, branchKey: 'stable', suffix: '']
]
if (developTrackEnabled) {
  environments << [name: 'develop', namespace: namespaces.develop, branchKey: 'develop', suffix: '-develop']
}

// ---------------------------------------------------------------------------
// Prune resources that should not exist for the current configuration.
// Idempotent - no-ops if already absent.
//   * 'pac-dev' Folder: the pre-v0.5 dual-branch model that nested develop
//     variants in a Folder. Always obsolete - never recreated.
//   * 'microservices-develop' ListView: only valid when the develop tier is
//     enabled (recreated below). Prune it when the tier is OFF so that turning
//     the flag off cleans up the stale view.
// ---------------------------------------------------------------------------
def jenkinsInst = jenkins.model.Jenkins.get()

def legacyFolder = jenkinsInst.getItem('pac-dev')
if (legacyFolder) {
    legacyFolder.delete()
    println "[seed] Pruned legacy folder: pac-dev"
}

if (!developTrackEnabled) {
    def staleView = jenkinsInst.getView('microservices-develop')
    if (staleView) {
        jenkinsInst.deleteView(staleView)
        println "[seed] Pruned 'microservices-develop' view (develop track disabled)"
    }
}

// ---------------------------------------------------------------------------
// For each environment: a pipeline job per service + a k6 smoke job, plus one
// ListView. 'stable' jobs keep bare names; 'develop' jobs get a '-develop'
// suffix so both tiers coexist at the root.
// ---------------------------------------------------------------------------
environments.each { e ->
  registry.services.each { svc ->
    def jobName = "${svc.name}${e.suffix}"
    def branch  = svc.branches?.get(e.branchKey) ?: gitFlowRefs[e.branchKey]

    pipelineJob(jobName) {
      description("Microservices '${svc.name}' (${e.name}) - builds '${branch}' and deploys to namespace '${e.namespace}'. Tracked via branch '${infraBranch}' of jenkins-2026.")
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
    targetNamespace: '${e.namespace}',
    envName: '${e.name}',
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

  // k6 smoke test job for this environment.
  pipelineJob("microservices-k6-smoke${e.suffix}") {
    description("Microservices Grafana observability smoke test (k6, ${e.name}). Tracked via branch '${infraBranch}' of jenkins-2026.")
    keepDependencies(false)
    logRotator { numToKeep(20) }

    definition {
      cps {
        script("""
@Library("microservices-shared-library@${pipelineRepoBranch}") _
MicroservicesK6SmokePipeline(
    targetNamespace: '${e.namespace}',
    envName: '${e.name}',
    genaiEnabled: ${genaiServiceEnabled},
    vus: '4',
    iterations: '12'
)
""".stripIndent())
        sandbox(true)
      }
    }
  }

  // One ListView per environment: 'microservices' (stable) / 'microservices-develop'.
  listView("microservices${e.suffix}") {
    jobs {
      registry.services.each { name("${it.name}${e.suffix}") }
      name("microservices-k6-smoke${e.suffix}")
    }
    columns { status(); weather(); name(); lastSuccess(); lastFailure(); lastDuration(); buildButton() }
  }
}

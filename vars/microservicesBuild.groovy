/**
 * microservicesBuild(type: 'java'|'angular', module: '<maven-module-or-empty>')
 *
 * Compiles and unit-tests the Microservices service. Runs inside the
 * 'maven' or 'node' container of the pod template defined in
 * jenkins/pipelines/Jenkinsfile.microservices.
 */
def call(Map cfg) {
  echo "Simulated Build & Test: skipping compilation and tests for ${cfg.type} (module: ${cfg.module ?: 'root'})"
}

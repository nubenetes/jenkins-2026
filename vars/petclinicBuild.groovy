/**
 * petclinicBuild(type: 'java'|'angular', module: '<maven-module-or-empty>')
 *
 * Compiles and unit-tests the PetClinic service. Runs inside the
 * 'maven' or 'node' container of the pod template defined in
 * jenkins/pipelines/Jenkinsfile.petclinic.
 */
def call(Map cfg) {
  if (cfg.type == 'java') {
    container('maven') {
      sh """
        set -eux
        unset MAVEN_CONFIG
        ./mvnw -B -pl ${cfg.module} -am -DskipITs clean verify
      """
    }
  } else if (cfg.type == 'angular') {
    container('node') {
      sh """
        set -eux
        npm ci
        npm run build -- --configuration production
      """
      // NOTE: `npm test` (Karma/Jasmine) needs a Chrome-enabled image and is
      // left as an extension point - swap the 'node' container image for one
      // that bundles headless Chrome and uncomment:
      // sh "npm test -- --watch=false --browsers=ChromeHeadless"
    }
  } else {
    error("petclinicBuild: unknown SERVICE_TYPE '${cfg.type}' (expected 'java' or 'angular')")
  }
}

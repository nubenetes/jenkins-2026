/**
 * microservicesBuild(type: 'java'|'angular', module: '<maven-module-or-empty>')
 *
 * Compiles and unit-tests the Microservices service. Runs inside the
 * 'maven' or 'node' container of the pod template defined in
 * jenkins/pipelines/Jenkinsfile.microservices.
 */
def call(Map cfg) {
  if (cfg.type == 'java') {
    container('maven') {
      sh """
        set -eux
        unset MAVEN_CONFIG
        export MAVEN_OPTS="-Xmx2048m -XX:+UseG1GC -XX:+ExitOnOutOfMemoryError"
        export NODE_OPTIONS="--max-old-space-size=3072"
        if [ -n "${cfg.module}" ] && [ -f "${cfg.module}/mvnw" ]; then
          cd ${cfg.module}
          ./mvnw -B -ntp -T 4 -s ${env.WORKSPACE}/jenkins-2026-infra/jenkins/maven-settings.xml -DskipITs -Dmaven.compiler.maxmem=1024m -DargLine="-Xmx1536m" clean verify
        elif [ -n "${cfg.module}" ]; then
          ./mvnw -B -ntp -T 4 -s ${env.WORKSPACE}/jenkins-2026-infra/jenkins/maven-settings.xml -pl ${cfg.module} -am -DskipITs -Dmaven.compiler.maxmem=1024m -DargLine="-Xmx1536m" clean verify
        else
          ./mvnw -B -ntp -T 4 -s ${env.WORKSPACE}/jenkins-2026-infra/jenkins/maven-settings.xml -DskipITs -Dmaven.compiler.maxmem=1024m -DargLine="-Xmx1536m" clean verify
        fi
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
    error("microservicesBuild: unknown SERVICE_TYPE '${cfg.type}' (expected 'java' or 'angular')")
  }
}

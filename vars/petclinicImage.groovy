/**
 * petclinicImage(type: 'java'|'angular', module: '<maven-module-or-empty>',
 *                 image: '<registry>/<repo>:<tag>', registryHost: '<registry-host>')
 *
 * Builds a container image for the service and pushes it to PETCLINIC_REGISTRY.
 *
 * - java:    `mvn spring-boot:build-image` (Cloud Native Buildpacks) talking
 *            to the dind sidecar via DOCKER_HOST, then `docker push` in the
 *            'docker' container.
 * - angular: plain `docker build` using resources/angular/Dockerfile (this
 *            repo) against the `dist/` produced by petclinicBuild.
 */
def call(Map cfg) {
  container('docker') {
    withCredentials([usernamePassword(credentialsId: 'container-registry', usernameVariable: 'REG_USER', passwordVariable: 'REG_PASS')]) {
      sh """
        set -eux
        echo "\$REG_PASS" | docker login ${cfg.registryHost} -u "\$REG_USER" --password-stdin
      """
    }
  }

  if (cfg.type == 'java') {
    container('maven') {
      sh """
        set -eux
        ./mvnw -B -pl ${cfg.module} -am -DskipTests spring-boot:build-image \
          -Dspring-boot.build-image.imageName=${cfg.image} \
          -Dspring-boot.build-image.publish=false
      """
    }
  } else if (cfg.type == 'angular') {
    container('docker') {
      // Build context is the jenkins-2026 checkout root (env.WORKSPACE), NOT
      // the petclinic-src checkout, so the Dockerfile can COPY both the app
      // source (petclinic-src/) and our nginx/OTel-web assets
      // (resources/angular/). See resources/angular/Dockerfile.
      sh """
        set -eux
        docker build -t ${cfg.image} -f ${env.WORKSPACE}/resources/angular/Dockerfile ${env.WORKSPACE}
      """
    }
  } else {
    error("petclinicImage: unknown SERVICE_TYPE '${cfg.type}' (expected 'java' or 'angular')")
  }

  container('docker') {
    sh "docker push ${cfg.image}"
  }
}

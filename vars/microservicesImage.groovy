/**
 * microservicesImage(type: 'java'|'angular', module: '<maven-module-or-empty>',
 *                 image: '<registry>/<repo>:<tag>', registryHost: '<registry-host>')
 *
 * Builds a container image for the service and pushes it to MICROSERVICES_REGISTRY.
 *
 * - java:    `mvn spring-boot:build-image` (Cloud Native Buildpacks) talking
 *            to the dind sidecar via DOCKER_HOST, then `docker push` in the
 *            'docker' container.
 * - angular: plain `docker build` using resources/angular/Dockerfile (this
 *            repo) against the `dist/` produced by microservicesBuild.
 */
def call(Map cfg) {
  def needsDockerPush = true

  withCredentials([usernamePassword(credentialsId: 'container-registry', usernameVariable: 'REG_USER', passwordVariable: 'REG_PASS')]) {
    container('docker') {
      sh """
        set -eux
        echo "\$REG_PASS" | docker login ${cfg.registryHost} -u "\$REG_USER" --password-stdin
      """
    }

    if (cfg.type == 'java') {
      container('maven') {
        sh """
          set -eux
          unset MAVEN_CONFIG
          export MAVEN_OPTS="-Xmx1024m -XX:+UseSerialGC"
          # Check if we are in a subfolder or monorepo
          BUILD_DIR="."
          if [ -n "${cfg.module}" ] && [ -f "${cfg.module}/mvnw" ]; then
            BUILD_DIR="${cfg.module}"
          fi

          cd \$BUILD_DIR

          # Try Jib first (modern preference), then fallback to spring-boot:build-image
          if grep -q "jib-maven-plugin" pom.xml; then
             ./mvnw -B -Pprod -DskipTests -Dmaven.compiler.maxmem=512m jib:build -Djib.to.image=${cfg.image} \
               -Djib.to.auth.username=\$REG_USER -Djib.to.auth.password=\$REG_PASS \
               -Djib.serialize=true
             # Jib pushes directly, so we flag it to skip local docker push
             echo "JIB_PUSHED" > ${env.WORKSPACE}/jib_pushed.txt
          else
             if [ -n "${cfg.module}" ]; then
               ./mvnw -B -pl ${cfg.module} -am -Pprod -DskipTests -Dmaven.compiler.maxmem=512m spring-boot:build-image \
                 -Dspring-boot.build-image.imageName=${cfg.image} \
                 -Dspring-boot.build-image.publish=false
             else
               ./mvnw -B -Pprod -DskipTests -Dmaven.compiler.maxmem=512m spring-boot:build-image \
                 -Dspring-boot.build-image.imageName=${cfg.image} \
                 -Dspring-boot.build-image.publish=false
             fi
          fi
        """
      }
      // Check if Jib pushed the image
      if (fileExists("${env.WORKSPACE}/jib_pushed.txt")) {
        needsDockerPush = false
        sh "rm -f ${env.WORKSPACE}/jib_pushed.txt"
      }
    } else if (cfg.type == 'angular') {
      container('docker') {
        // Build context is the jenkins-2026 checkout root (env.WORKSPACE), NOT
        // the microservices-src checkout, so the Dockerfile can COPY both the app
        // source (microservices-src/) and our nginx/OTel-web assets
        // (resources/angular/). See resources/angular/Dockerfile.
        sh """
          set -eux
          docker build -t ${cfg.image} -f ${env.WORKSPACE}/resources/angular/Dockerfile ${env.WORKSPACE}
        """
      }
    } else {
      error("microservicesImage: unknown SERVICE_TYPE '${cfg.type}' (expected 'java' or 'angular')")
    }

    if (needsDockerPush) {
      container('docker') {
        sh "docker push ${cfg.image}"
      }
    } else {
      echo "Image was already pushed directly by Jib, skipping docker push."
    }
  }
}

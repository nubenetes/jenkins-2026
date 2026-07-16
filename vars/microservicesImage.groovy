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
  // Digest of the image Jib actually pushed, read from its own output file (below).
  // Empty for the non-Jib paths; see the signing block at the end.
  def jibDigest = ''

  // Binary Authorization attests a DIGEST, and a :tag cannot be resolved back to one
  // here — `gcloud container images describe` only speaks GCR/AR, and GHCR (this repo's
  // registry) 403s even an authenticated manifest HEAD (verified live). Jib knows the
  // digest of what it just pushed for free and writes target/jib-image.digest (its
  // default jib.outputPaths.digest), so grab it for the signing step at the end. Copied
  // to a fixed path because BUILD_DIR varies by module.
  //
  // GATED ON THE FLAG, and deliberately so: with Binary Authorization off nothing reads
  // this, and an unconditional `cp` inside `set -eux` would fail the build for EVERY
  // service if Jib ever stopped emitting the file — i.e. an opt-in feature breaking the
  // default path. Off → not even attempted; on → it must work, and the check after the
  // build errors loudly rather than skipping the signature. See docs/507 § Pipeline wiring.
  String jibDigestCopy = (env.BINAUTHZ_ENABLED == 'true')
    ? "\n             cp target/jib-image.digest ${env.WORKSPACE}/jib_image_digest.txt"
    : ""

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
          # G1 (not SerialGC — single-threaded, poor on the multi-core build agent) +
          # fail-fast on OOM, consistent with the runtime/controller JVM tuning (docs/303).
          export MAVEN_OPTS="-Xmx1024m -XX:+UseG1GC -XX:+ExitOnOutOfMemoryError"
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
             echo "JIB_PUSHED" > ${env.WORKSPACE}/jib_pushed.txt${jibDigestCopy}
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
        // Pick up the digest Jib recorded for the image it just pushed. Only required
        // when we are actually going to sign — but do NOT quietly skip if it's missing
        // then: a signing step that silently attests nothing is worse than a red build.
        if (fileExists("${env.WORKSPACE}/jib_image_digest.txt")) {
          jibDigest = readFile("${env.WORKSPACE}/jib_image_digest.txt").trim()
          sh "rm -f ${env.WORKSPACE}/jib_image_digest.txt"
        }
        if (env.BINAUTHZ_ENABLED == 'true' && !jibDigest) {
          error("microservicesImage: Jib pushed ${cfg.image} but left no target/jib-image.digest, " +
                "and Binary Authorization is ON — refusing to continue rather than skip signing silently.")
        }
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

    // Binary Authorization (opt-in, docs/507 § Pipeline wiring): sign + attest the
    // pushed image DIGEST via the single-source resources/sign-and-attest-image.sh,
    // materialised from the shared library like patch-app-source.sh. NO-OP unless
    // BINAUTHZ_ENABLED=true. Runs in the 'gcloud' container (added to the pod template
    // by MicroservicesPipeline.groovy only when the flag is on); gcloud auths via the
    // 'jenkins' agent KSA Workload Identity (bind it to the signer GSA terraform/gke grants).
    // Pass the image BY DIGEST when Jib gave us one (image@sha256:… — the script then
    // attests it directly instead of trying to resolve the :tag, which it cannot do for
    // GHCR: `gcloud container images describe` is GCR/AR-only and the crane fallback is
    // absent from google/cloud-sdk:slim, so a tag here fails with "could not resolve a
    // digest" — the build that surfaced this). The non-Jib (buildpacks) path still passes
    // the tag; it is GCR/AR-friendly and the script's own resolution covers it.
    if (env.BINAUTHZ_ENABLED == 'true') {
      def signTarget = jibDigest ? "${cfg.image.split(':')[0..-2].join(':')}@${jibDigest}" : cfg.image
      container('gcloud') {
        writeFile file: '.sign-and-attest-image.sh', text: libraryResource('sign-and-attest-image.sh')
        sh "BINAUTHZ_ENABLED=true bash .sign-and-attest-image.sh '${signTarget}'"
      }
    }
  }
}

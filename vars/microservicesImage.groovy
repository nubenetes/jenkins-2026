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
  echo "Simulated Build & Push Image: skipping docker build and push for ${cfg.type} (image: ${cfg.image})"
}

/**
 * petclinicSmokeTest(serviceName: '<svc>', namespace: '<ns>',
 *                     port: '<port>', healthPath: '/actuator/health')
 *
 * Waits for the rollout to finish, then runs a throwaway curl pod against
 * the in-cluster Service to verify the health endpoint responds.
 */
def call(Map cfg) {
  container('helm') {
    sh """
      set -eux
      kubectl -n ${cfg.namespace} rollout status deployment/${cfg.serviceName} --timeout=180s
      kubectl -n ${cfg.namespace} run smoke-${cfg.serviceName}-${env.BUILD_NUMBER} \
        --rm -i --restart=Never --image=curlimages/curl:8.10.1 \
        --command -- curl -sf --max-time 10 \
        http://${cfg.serviceName}.${cfg.namespace}.svc.cluster.local:${cfg.port}${cfg.healthPath}
    """
  }
}

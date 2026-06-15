/**
 * microservicesSmokeTest(serviceName: '<svc>', namespace: '<ns>',
 *                     port: '<port>', healthPath: '/actuator/health')
 *
 * Waits for the rollout to finish, then runs a throwaway curl pod against
 * the in-cluster Service to verify the health endpoint responds.
 */
def call(Map cfg) {
  container('helm') {
    sh """
      set -eux
      # Service endpoints/kube-proxy/CNI can take a few seconds to catch up
      # with a just-finished rollout, so a fresh pod's first connection can
      # time out even though the new Pods are Ready - retry on any error.
      kubectl -n ${cfg.namespace} run smoke-${cfg.serviceName}-${env.BUILD_NUMBER} \
        --rm -i --restart=Never --image=curlimages/curl:8.10.1 \
        --command -- curl -sf --connect-timeout 5 --max-time 60 \
        --retry 5 --retry-delay 3 --retry-all-errors \
        http://${cfg.serviceName}.${cfg.namespace}.svc.cluster.local:${cfg.port}${cfg.healthPath}
    """
  }
}

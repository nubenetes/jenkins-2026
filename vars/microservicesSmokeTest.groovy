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
      # Run the throwaway curl pod in the AGENT's OWN namespace (jenkins), NOT the
      # target microservices namespace. Under NetworkPolicy enforcement (GKE Dataplane
      # V2) the microservices namespace is default-deny egress (DNS only) and the
      # microservice only accepts ingress from the gateway pod or the CI namespaces —
      # so a curl pod created there can neither egress nor be accepted, and the health
      # check times out (curl exit 28). Instead: create it in the jenkins namespace
      # (microservice-policy allows that namespace's ingress) and label it
      # jenkins=slave so jenkins-agent-policy grants it open egress — the same path the
      # build agents use. The target stays the microservices-namespace Service FQDN.
      #
      # Service endpoints/kube-proxy/CNI can also lag a just-finished rollout, so a
      # fresh pod's first connection can time out even when Pods are Ready - retry.
      ns="\$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)"
      protocol="http"
      curl_opts=""
      if [ "${cfg.serviceName}" = "gateway" ] && kubectl -n "${cfg.namespace}" get secret gateway-tls >/dev/null 2>&1; then
        protocol="https"
        curl_opts="-k"
      fi
      kubectl -n "\$ns" run smoke-${cfg.serviceName}-${env.BUILD_NUMBER} \
        --rm -i --restart=Never --image=curlimages/curl:8.10.1 \
        --labels=jenkins=slave \
        --command -- curl -sf --connect-timeout 5 --max-time 60 \
        --retry 5 --retry-delay 3 --retry-all-errors \$curl_opts \
        \$protocol://${cfg.serviceName}.${cfg.namespace}.svc.cluster.local:${cfg.port}${cfg.healthPath}
    """
  }
}

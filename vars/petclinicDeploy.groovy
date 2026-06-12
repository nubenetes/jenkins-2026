/**
 * petclinicDeploy(serviceName: '<svc>', envName: 'stable'|'develop',
 *                  namespace: '<ns>', platform: 'gke'|'eks'|'aks'|'openshift',
 *                  tag: '<image-tag>')
 *
 * Upgrades (or installs) the shared helm/petclinic release for this
 * environment, overriding only the image tag of the service this pipeline
 * just built. The 'jenkins' ServiceAccount is bound to 'edit' in the
 * petclinic/petclinic-develop namespaces (see helm/jenkins/rbac/).
 */
def call(Map cfg) {
  container('helm') {
    sh """
      set -eux
      helm upgrade --install petclinic-${cfg.envName} ${env.WORKSPACE}/helm/petclinic \
        -f ${env.WORKSPACE}/helm/petclinic/values-${cfg.envName}.yaml \
        --set global.platform=${cfg.platform} \
        --set services.${cfg.serviceName}.image.tag=${cfg.tag} \
        --namespace ${cfg.namespace} --create-namespace \
        --wait --timeout 5m
    """
  }
}

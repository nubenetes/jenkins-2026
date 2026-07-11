/**
 * microservicesK6Run(cfg)
 *
 * Resolves the effective k6 workload for a MicroservicesK6SmokePipeline run and
 * hands it to microservicesK6Smoke (the K6SIM_* contract). Precedence, highest
 * first:
 *
 *   1. a non-empty manual build parameter (params.*)
 *   2. the selected committed preset (jenkins/pipelines/k6/presets/<name>.yaml,
 *      chosen via params.PRESET; 'none' = pure manual)
 *   3. the seed-baked cfg defaults (services.yaml via seed_jobs.groovy)
 *   4. '' → the k6 script's own default (microservices-smoke.js)
 *
 * Extracted verbatim from the pipeline's former script {} block: per the
 * Declarative-first rule (docs/403), merge logic lives in a library custom step
 * and the pipeline shell stays declarative. Reads the calling pipeline's global
 * `params` (build parameters) directly.
 */
def call(Map cfg) {
  // Load the selected preset (committed YAML) if any, then merge:
  // a non-empty manual field overrides the preset; the preset
  // overrides the script default. PROFILE (a choice, always has a
  // value) is taken from the preset when one is selected.
  def preset = [:]
  if (params.PRESET && params.PRESET != 'none') {
    def f = "jenkins/pipelines/k6/presets/${params.PRESET}.yaml"
    if (fileExists(f)) {
      preset = (readYaml(file: f).params ?: [:])
      echo "Loaded k6 preset '${params.PRESET}' from ${f}: ${preset}"
    } else {
      echo "WARNING: preset file ${f} not found - using manual inputs only."
    }
  }
  def usingPreset = !preset.isEmpty()
  def has = { v -> v != null && v.toString().trim() != '' }
  // manual non-empty wins, else preset value, else '' (script default)
  def pick = { manual, key -> has(manual) ? manual.toString() : (preset[key] != null ? preset[key].toString() : '') }

  // Coalesce preset -> build-param -> seed-baked cfg -> sane default.
  // The cfg fallback matters because Jenkins doesn't apply a job's
  // default param values on its FIRST build after the seed (re)defines
  // it, so params.TARGET_NAMESPACE can be null then (-> "null" namespace).
  microservicesK6Smoke(
      namespace:    preset.targetNamespace ?: params.TARGET_NAMESPACE ?: cfg.targetNamespace ?: 'microservices',
      envName:      preset.envName ?: params.ENV_NAME ?: cfg.envName ?: 'stable',
      targetUrl:    pick(params.TARGET_URL, 'targetUrl'),
      genaiEnabled: cfg.genaiEnabled,
      profile:      usingPreset ? (preset.profile ?: 'smoke') : params.PROFILE,
      vus:          pick(params.VUS, 'vus'),
      iterations:   pick(params.ITERATIONS, 'iterations'),
      duration:     pick(params.DURATION, 'duration'),
      stages:       pick(params.STAGES, 'stages'),
      rps:          pick(params.RPS, 'rps'),
      sleep:        pick(params.SLEEP, 'sleep'),
      scenarios:    pick(params.SCENARIOS, 'scenarios'),
      p95Ms:        pick(params.P95_MS, 'p95Ms'),
      errorRate:    pick(params.ERROR_RATE, 'errorRate'),
      debug:        params.DEBUG || (preset.debug?.toString() == 'true')
  )
}

// =============================================================================
// Microservices observability traffic generator (k6) — fully parametrizable.
//
// BACKWARD COMPATIBLE: with no env vars set this runs the original lightweight
// smoke test — profile=smoke, 4 VUs × 12 shared iterations (NOT a load test) of
// a simulated session against the in-cluster Services in TARGET_NAMESPACE — to
// give Grafana fresh traces/metrics/logs to correlate.
//
// Env vars unlock load / stress / soak / spike / breakpoint profiles, custom
// ramping stages, arrival-rate (RPS) control, tunable thresholds, think-time,
// endpoint ports, scenario (request-flow) selection and debug logging.
//
// CONTRACT (all optional; the same variables are wired through the Jenkins,
// Tekton, GitHub Actions and Argo Workflows runners). The workload knobs use a
// K6SIM_ prefix on purpose: k6 reserves K6_VUS / K6_DURATION / K6_ITERATIONS /
// K6_STAGES / K6_RPS as its own execution-option env vars, which would clash
// with the `scenarios` block below. See docs/302-K6_LOAD_TESTING.md for the
// full reference.
//
//   Target
//     TARGET_NAMESPACE        in-cluster DNS namespace      (default microservices)
//     TARGET_URL              external base URL; overrides in-cluster targeting
//     ENV_NAME                deployment.environment label  (default stable)   [*]
//     K6SIM_GATEWAY_PORT      gateway service port          (default 8080)
//     K6SIM_MICROSERVICE_PORT microservice service port     (default 8081)
//
//   Workload
//     K6SIM_PROFILE   smoke|load|stress|soak|spike|breakpoint (default smoke)
//     K6SIM_VUS       virtual users / pre-allocated VUs        (0 = profile default)
//     K6SIM_ITERATIONS shared iterations (smoke only)          (0 = profile default)
//     K6SIM_DURATION  hold duration, e.g. 30s / 2m / 1h        (overrides profile)
//     K6SIM_STAGES    ramping stages "30s:10,1m:50,30s:0"      (overrides profile)
//     K6SIM_RPS       constant arrival rate (req/s)            (overrides profile;
//                       breakpoint: sets the ramp target instead)
//     K6SIM_SLEEP     think-time seconds between requests      (default 0.3)
//
//   Scenarios (request flows; comma list or "all")
//     K6SIM_SCENARIOS gateway-ui,gateway-health,microservice-health,gateway-proxy
//
//   Thresholds / pass-fail budget
//     K6SIM_P95_MS      http_req_duration p(95) budget, ms     (default 3000)
//     K6SIM_ERROR_RATE  http_req_failed max rate (0..1)        (default 0.05)
//
//   Misc
//     K6SIM_WARMUP_TIMEOUT readiness-gate budget, seconds; 0=off  (default 60)
//     K6SIM_DEBUG       true → per-iteration console logging    (default false)
//
//   [*] ENV_NAME is surfaced as the deployment.environment OTel resource
//       attribute by the runner, not by this script; it is read here only for
//       the startup banner.
// =============================================================================

import http from 'k6/http';
import { check, sleep } from 'k6';

// ---- small env helpers ------------------------------------------------------
function envStr(name, def) {
  const v = __ENV[name];
  return v === undefined || v === '' ? def : v;
}
function envNum(name, def) {
  const v = __ENV[name];
  return v === undefined || v === '' ? def : Number(v);
}
function envBool(name, def) {
  const v = __ENV[name];
  if (v === undefined || v === '') return def;
  return ['1', 'true', 'yes', 'on'].includes(String(v).toLowerCase());
}

// ---- target -----------------------------------------------------------------
const NAMESPACE = envStr('TARGET_NAMESPACE', 'microservices');
const TARGET_URL = envStr('TARGET_URL', '');
const ENV_NAME = envStr('ENV_NAME', 'stable');
const GATEWAY_PORT = envNum('K6SIM_GATEWAY_PORT', 8080);
const MICROSERVICE_PORT = envNum('K6SIM_MICROSERVICE_PORT', 8081);
const SLEEP = envNum('K6SIM_SLEEP', 0.3);
const DEBUG = envBool('K6SIM_DEBUG', false);

function svcUrl(name, port, path = '') {
  if (TARGET_URL) {
    return `${TARGET_URL}${path}`;
  }
  const scheme = envStr(`K6SIM_${name.toUpperCase()}_SCHEME`, 'http');
  return `${scheme}://${name}.${NAMESPACE}.svc.cluster.local:${port}${path}`;
}

const API_GATEWAY = svcUrl('gateway', GATEWAY_PORT);
const MICROSERVICE = svcUrl('jhipstersamplemicroservice', MICROSERVICE_PORT);


// ---- scenario (request-flow) selection --------------------------------------
const ALL_FLOWS = ['gateway-ui', 'gateway-health', 'microservice-health', 'gateway-proxy'];
const FLOWS_RAW = envStr('K6SIM_SCENARIOS', 'all').toLowerCase();
const FLOWS = FLOWS_RAW === 'all'
  ? ALL_FLOWS
  : FLOWS_RAW.split(',').map((s) => s.trim()).filter((s) => ALL_FLOWS.includes(s));
const flow = (name) => FLOWS.includes(name);

// ---- thresholds -------------------------------------------------------------
const P95_MS = envNum('K6SIM_P95_MS', 3000);
const ERR_RATE = envNum('K6SIM_ERROR_RATE', 0.05);
// Readiness-gate budget (seconds). setup() polls the targets' health until they
// serve BEFORE the measured scenario starts, so a cold target (pod not Ready,
// no Service endpoints yet → the ~20s dial i/o timeout that flips a fresh
// develop deploy to UNSTABLE) doesn't blow the thresholds. 0 disables it.
const WARMUP_S = envNum('K6SIM_WARMUP_TIMEOUT', 60);

// ---- workload profile -------------------------------------------------------
const PROFILE = envStr('K6SIM_PROFILE', 'smoke').toLowerCase();
const VUS = envNum('K6SIM_VUS', 0); // 0 → use the profile default
const ITERATIONS = envNum('K6SIM_ITERATIONS', 0);
const DURATION = envStr('K6SIM_DURATION', '');
const STAGES_RAW = envStr('K6SIM_STAGES', ''); // "30s:10,1m:50,30s:0"
const RPS = envNum('K6SIM_RPS', 0);

function parseStages(raw) {
  return raw
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
    .map((s) => {
      const [dur, target] = s.split(':');
      return { duration: dur.trim(), target: Number(target) };
    });
}

// Build the single k6 scenario. Explicit overrides (STAGES, RPS) win over the
// profile preset; within a preset, VUS / DURATION / ITERATIONS fine-tune it.
// Exception: profile=breakpoint consumes RPS itself — it IS an RPS ramp, and
// RPS sets the ramp's target (see the breakpoint case below). Letting the flat
// constant-arrival-rate override swallow RPS here would replace the 1→RPS
// "find the knee" ramp with a constant blast at the target rate.
function buildScenario() {
  if (STAGES_RAW) {
    return { executor: 'ramping-vus', startVUs: 0, stages: parseStages(STAGES_RAW), gracefulRampDown: '10s' };
  }
  if (RPS > 0 && PROFILE !== 'breakpoint') {
    const pre = VUS || Math.max(10, Math.ceil(RPS));
    return {
      executor: 'constant-arrival-rate',
      rate: RPS,
      timeUnit: '1s',
      duration: DURATION || '1m',
      preAllocatedVUs: pre,
      maxVUs: pre * 5,
    };
  }

  switch (PROFILE) {
    case 'load': {
      const peak = VUS || 20;
      return {
        executor: 'ramping-vus',
        startVUs: 0,
        gracefulRampDown: '15s',
        stages: [
          { duration: '30s', target: peak },
          { duration: DURATION || '2m', target: peak },
          { duration: '30s', target: 0 },
        ],
      };
    }
    case 'stress': {
      const base = VUS || 50;
      return {
        executor: 'ramping-vus',
        startVUs: 0,
        gracefulRampDown: '15s',
        stages: [
          { duration: '1m', target: base },
          { duration: '2m', target: base * 2 },
          { duration: DURATION || '2m', target: base * 2 },
          { duration: '1m', target: 0 },
        ],
      };
    }
    case 'soak':
      return { executor: 'constant-vus', vus: VUS || 10, duration: DURATION || '1h' };
    case 'spike': {
      const peak = VUS || 100;
      return {
        executor: 'ramping-vus',
        startVUs: 0,
        gracefulRampDown: '10s',
        stages: [
          { duration: '10s', target: peak },
          { duration: DURATION || '1m', target: peak },
          { duration: '10s', target: 0 },
        ],
      };
    }
    case 'breakpoint': {
      const pre = VUS || 50;
      return {
        executor: 'ramping-arrival-rate',
        startRate: 1,
        timeUnit: '1s',
        preAllocatedVUs: pre,
        maxVUs: pre * 10,
        stages: [{ duration: DURATION || '5m', target: RPS || 200 }],
      };
    }
    case 'smoke':
    default:
      // Original behaviour: a few VUs sharing a small fixed iteration budget.
      // If a DURATION is given, hold those VUs for that long instead.
      return DURATION
        ? { executor: 'constant-vus', vus: VUS || 4, duration: DURATION }
        : { executor: 'shared-iterations', vus: VUS || 4, iterations: ITERATIONS || 12 };
  }
}

// breakpoint deliberately pushes past the latency budget to find the knee, so
// it aborts the run when the p(95) threshold is crossed; every other profile
// only *flags* a breach (k6 exits 99) so the run still feeds Grafana.
const abortOnFail = PROFILE === 'breakpoint';

// The one measured scenario. Named so the thresholds can be scoped to it —
// setup()'s warm-up traffic is NOT tagged scenario:<SCENARIO> (verified against
// a live run), so scoping excludes it and the cold-start probe never trips a
// threshold. Keep this name in sync with the summary readers (the Jenkins
// printK6Summary + this file's handleSummary prefer the scenario:<SCENARIO>
// sub-metric for the headline latency/error numbers).
const SCENARIO = 'microservices';

export const options = {
  insecureSkipTLSVerify: true,
  scenarios: { [SCENARIO]: buildScenario() },
  thresholds: {
    // Scoped to the measured scenario (see SCENARIO above) so the setup()
    // readiness gate's requests are excluded — otherwise a cold-start dial
    // timeout during warm-up would breach these and falsely mark UNSTABLE.
    [`http_req_failed{scenario:${SCENARIO}}`]: [{ threshold: `rate<${ERR_RATE}`, abortOnFail }],
    [`http_req_duration{scenario:${SCENARIO}}`]: [{ threshold: `p(95)<${P95_MS}`, abortOnFail }],
  },
  // setup() may poll up to WARMUP_S seconds; give it headroom over k6's 60s
  // default setupTimeout so a long cold start doesn't abort the whole run.
  setupTimeout: `${WARMUP_S + 30}s`,
  // Populate every percentile the CI summaries render (GHA jq + Jenkins parser
  // both print p99); k6's default trend stats omit p(99), so without this it
  // always showed p99=0.
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)'],
};


// ---- traceparent generation (so every iteration is one correlated trace) ----
function hex(len) {
  let s = '';
  for (let i = 0; i < len; i++) {
    s += Math.floor(Math.random() * 16).toString(16);
  }
  return s;
}

function newTraceparent() {
  return `00-${hex(32)}-${hex(16)}-01`;
}

function get(url, traceparent, name) {
  const res = http.get(url, {
    headers: { traceparent },
    tags: { name },
  });
  check(res, { [`${name} is healthy`]: (r) => r.status >= 200 && r.status < 400 });
  return res;
}

// Log the resolved configuration at VU init time for traceability in the logs.
if (DEBUG) {
  console.log(
    `[k6-sim] profile=${PROFILE} env=${ENV_NAME} target=${TARGET_URL || `in-cluster/${NAMESPACE}`} ` +
    `flows=${FLOWS.join('|')} p95<${P95_MS}ms err<${ERR_RATE}`
  );
}

// ---- readiness gate (runs ONCE before the measured scenario) ----------------
// Absorbs cold start: a just-deployed target whose pod isn't Ready has no
// Service endpoints, so the first requests hang until the ~20s dial i/o timeout
// — exactly what flips a fresh develop deploy to UNSTABLE. Poll each target's
// health with a short per-attempt timeout until it serves (2xx/3xx) or the
// shared WARMUP_S budget runs out. setup() traffic is excluded from the
// scenario-scoped thresholds, so these probes never count toward pass/fail.
// Bounded on purpose: if a target never comes up we STILL run the test, so the
// smoke surfaces the failure via checks instead of hanging the build.
export function setup() {
  if (WARMUP_S <= 0) return;
  const targets = [];
  if (TARGET_URL) {
    // External runs hit the public gateway for every flow.
    targets.push({ name: 'target', url: `${TARGET_URL}/management/health` });
  } else {
    if (flow('gateway-ui') || flow('gateway-health') || flow('gateway-proxy')) {
      targets.push({ name: 'gateway', url: `${API_GATEWAY}/management/health` });
    }
    if (flow('microservice-health')) {
      // Readiness (not full health): the lightweight "pod is serving" signal
      // that clears the dial timeout; proven reachable (the gateway-proxy flow
      // hits this same path via the gateway).
      targets.push({ name: 'microservice', url: `${MICROSERVICE}/management/health/readiness` });
    }
  }
  const deadline = Date.now() + WARMUP_S * 1000;
  for (const t of targets) {
    let ready = false;
    while (Date.now() < deadline) {
      const r = http.get(t.url, { timeout: '2s', tags: { warmup: 'true' } });
      if (r.status >= 200 && r.status < 400) { ready = true; break; }
      sleep(2);
    }
    console.log(`[k6-warmup] ${t.name}: ${ready ? 'ready' : `NOT ready after ${WARMUP_S}s — running anyway`} (${t.url})`);
  }
}

export default function () {
  const traceparent = newTraceparent();
  if (DEBUG) {
    console.log(`[k6-sim] iteration trace_id=${traceparent.split('-')[1]}`);
  }

  // 1. Gateway UI landing page
  if (flow('gateway-ui')) {
    get(`${API_GATEWAY}/`, traceparent, 'gateway-ui-root');
    sleep(SLEEP);
  }

  // 2. Gateway health check
  if (flow('gateway-health')) {
    get(`${API_GATEWAY}/management/health`, traceparent, 'gateway-health');
    sleep(SLEEP);
  }

  // 3. Microservice health check directly (only reachable in-cluster)
  if (flow('microservice-health') && !TARGET_URL) {
    get(`${MICROSERVICE}/management/health`, traceparent, 'microservice-health');
    sleep(SLEEP);
  }

  // 4. Microservice health via the Gateway proxy route (Option A verification)
  if (flow('gateway-proxy')) {
    get(`${API_GATEWAY}/services/jhipstersamplemicroservice/management/health/readiness`, traceparent, 'gateway-proxy-microservice-health');
    sleep(SLEEP);
  }
}

// ---- end-of-test summary ----------------------------------------------------
// Write the run summary as JSON for the CI engines to parse. Why handleSummary
// and not k6's --summary-export: k6 2.0's --summary-export emits a FLATTENED
// schema (metrics.<m>.<stat>) that silently broke EVERY consumer — the GHA jq,
// the Jenkins readJSON parser and the Tekton task all read
// metrics.<m>.values.<stat> and so saw all-zeros. handleSummary's `data` keeps
// the stable nested `.values.*` (+ `.thresholds[expr].ok`) schema those parsers
// expect, so emitting it here fixes all three engines from a single place.
// Output path is overridable via K6_SUMMARY_OUT — Tekton runs k6 from a
// sub-directory and reads the file from the workspace root, so it sets the
// absolute path; GHA/Jenkins use the CWD-relative default.
export function handleSummary(data) {
  const out = envStr('K6_SUMMARY_OUT', 'k6-summary.json');
  const m = data.metrics || {};
  const val = (name, stat) => {
    try {
      const x = m[name].values[stat];
      return x === undefined || x === null ? 0 : x;
    } catch (e) {
      return 0;
    }
  };
  // Prefer the scenario-scoped sub-metric for the headline latency/error numbers
  // so the setup() warm-up traffic doesn't skew what's shown (it's excluded from
  // the thresholds, so the display should match); fall back to the top-level
  // metric for older summaries / when scoping is absent.
  const SCEN = `{scenario:${SCENARIO}}`;
  const primary = (name) => (m[name + SCEN] && m[name + SCEN].values) ? name + SCEN : name;
  const thr = [];
  for (const [name, metric] of Object.entries(m)) {
    for (const [expr, res] of Object.entries(metric.thresholds || {})) {
      const ok = typeof res === 'object' ? res.ok : res;
      thr.push(`  [${ok === false ? 'FAIL' : 'PASS'}] ${name}: ${expr}`);
    }
  }
  // Per-check pass/fail tree. Defining handleSummary SUPPRESSES k6's own
  // end-of-test summary — which is exactly what prints the ✓/✗ breakdown per
  // named check. Without reproducing it here the CI log shows only the aggregate
  // "44/48 passed" and NOT which flow broke, so you'd have to crack open
  // k6-summary.json to find it. Walk root_group (+ nested groups) and mark each
  // named check; this text then shows up in every engine's log (all four run
  // this same script and echo its stdout).
  const checkLines = (group, indent) => {
    const lines = [];
    for (const c of group.checks || []) {
      const fails = c.fails || 0;
      const total = (c.passes || 0) + fails;
      lines.push(
        `  ${indent}[${fails === 0 ? 'PASS' : 'FAIL'}] ${c.name}: ${c.passes || 0}/${total}` +
        (fails ? `  <-- ${fails} failed` : '')
      );
    }
    for (const g of group.groups || []) {
      if (g.name) lines.push(`  ${indent}# ${g.name}`);
      lines.push(...checkLines(g, indent + '  '));
    }
    return lines;
  };
  const checks = checkLines(data.root_group || {}, '');
  const passed = val('checks', 'passes');
  const stdout =
    [
      '',
      '========== k6 run summary ==========',
      `checks:   ${passed}/${passed + val('checks', 'fails')} passed`,
      `requests: ${val('http_reqs', 'count')} total, ${(val(primary('http_req_failed'), 'rate') * 100).toFixed(2)}% failed`,
      `latency:  avg=${Math.round(val(primary('http_req_duration'), 'avg'))}ms p95=${Math.round(val(primary('http_req_duration'), 'p(95)'))}ms`,
      `volume:   ${val('iterations', 'count')} iters, peak ${val('vus_max', 'value')} VUs`,
      '--- checks (per flow) ---',
      ...(checks.length ? checks : ['  (none)']),
      '--- thresholds ---',
      ...(thr.length ? thr : ['  (none)']),
      '====================================',
      '',
    ].join('\n');
  return { [out]: JSON.stringify(data), stdout };
}

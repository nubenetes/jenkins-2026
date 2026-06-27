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
// Tekton and GitHub Actions runners). The workload knobs use a K6SIM_ prefix on
// purpose: k6 reserves K6_VUS / K6_DURATION / K6_ITERATIONS / K6_STAGES / K6_RPS
// as its own execution-option env vars, which would clash with the `scenarios`
// block below. See docs/302-K6_LOAD_TESTING.md for the full reference.
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
//     K6SIM_RPS       constant arrival rate (req/s)            (overrides profile)
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
  return `http://${name}.${NAMESPACE}.svc.cluster.local:${port}${path}`;
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
function buildScenario() {
  if (STAGES_RAW) {
    return { executor: 'ramping-vus', startVUs: 0, stages: parseStages(STAGES_RAW), gracefulRampDown: '10s' };
  }
  if (RPS > 0) {
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

export const options = {
  scenarios: { microservices: buildScenario() },
  thresholds: {
    http_req_failed: [{ threshold: `rate<${ERR_RATE}`, abortOnFail }],
    http_req_duration: [{ threshold: `p(95)<${P95_MS}`, abortOnFail }],
  },
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

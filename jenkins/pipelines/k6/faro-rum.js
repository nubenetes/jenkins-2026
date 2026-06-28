// =============================================================================
// faro-rum.js — k6 synthetic Grafana Faro RUM beacon generator
// =============================================================================
// A DEDICATED k6 test type (profile `rum`) that does NOT load-test the
// microservices. Instead each iteration = one synthetic browser SESSION: it
// POSTs a Grafana Faro beacon (page-load log + Core Web Vitals measurement +
// a browser documentLoad span; a configurable fraction also POST a JS
// exception) to the otel-collector's **faro receiver**. The collector converts
// them to OTLP logs+traces and ships them to Loki/Tempo, populating the
// "CI-CD Frontend RUM (Angular / Faro)" dashboard — the same path a real
// browser running the Angular Faro Web SDK uses (see docs/202), before/without
// real browser traffic.
//
// ⚠️ Backend support: RUM/Faro is native only on **oss** and **grafana-cloud**
// (both store the Faro logs/traces in Loki/Tempo). On managed-azure/managed-aws
// Faro degrades to generic App Insights/CloudWatch, so the runner skips this
// test type there (see .github/workflows/Day2.traffic.01-k6.yml). docs/302.
//
// Contract (K6SIM_* / __ENV, resolved by the runner from the preset + overrides):
//   FARO_URL          faro receiver base URL (e.g. http://localhost:8027/ via PF)
//   ENV_NAME          deployment.environment tag (develop | stable)
//   K6SIM_VUS         concurrent synthetic browsers (default 5)
//   K6SIM_ITERATIONS  total sessions to emit (default 40; shared-iterations)
//   K6SIM_DURATION    if set → constant-vus for this long instead of a fixed count
//   K6SIM_ERROR_RATE  fraction of sessions that also emit a JS exception (default 0.2)
//   K6SIM_P95_MS      p95 budget (ms) for the beacon POST latency (default 1500)
//   K6SIM_DEBUG       "true" → per-iteration logging
// =============================================================================
import http from "k6/http";
import { check } from "k6";
import { Counter, Trend } from "k6/metrics";

const FARO_URL = (__ENV.FARO_URL || "http://localhost:8027/").replace(/\/?$/, "/");
const ENV_NAME = __ENV.ENV_NAME || "develop";
const VUS = parseInt(__ENV.K6SIM_VUS || "5", 10);
const ITERATIONS = parseInt(__ENV.K6SIM_ITERATIONS || "40", 10);
const DURATION = __ENV.K6SIM_DURATION || "";
const ERROR_RATE = parseFloat(__ENV.K6SIM_ERROR_RATE || "0.2");
const P95_MS = parseInt(__ENV.K6SIM_P95_MS || "1500", 10);
const DEBUG = (__ENV.K6SIM_DEBUG || "").toLowerCase() === "true";

// --- custom metrics (tagged k6_profile=rum by the runner --tag) --------------
const beaconsSent = new Counter("rum_beacons_sent");
const beaconsFailed = new Counter("rum_beacons_failed");
const exceptionsSent = new Counter("rum_exceptions_sent");
const lcp = new Trend("rum_web_vital_lcp_ms", true);
const fcp = new Trend("rum_web_vital_fcp_ms", true);
const ttfb = new Trend("rum_web_vital_ttfb_ms", true);
const inp = new Trend("rum_web_vital_inp_ms", true);

// constant-vus when a DURATION is given (continuous), else a fixed session count.
const scenarios = DURATION
  ? { rum: { executor: "constant-vus", vus: VUS, duration: DURATION } }
  : { rum: { executor: "shared-iterations", vus: VUS, iterations: ITERATIONS, maxDuration: "10m" } };

export const options = {
  scenarios,
  thresholds: {
    // beacon POSTs should be accepted (2xx/202) and reasonably fast
    http_req_failed: [`rate<${ERROR_RATE > 0 ? 0.05 : 0.01}`],
    http_req_duration: [`p(95)<${P95_MS}`],
    rum_beacons_failed: ["count<1"],
  },
};

const BROWSERS = [
  { name: "Chrome", version: "126", os: "Windows", mobile: false },
  { name: "Chrome", version: "126", os: "macOS", mobile: false },
  { name: "Firefox", version: "128", os: "Linux", mobile: false },
  { name: "Safari", version: "17", os: "iOS", mobile: true },
  { name: "Edge", version: "126", os: "Windows", mobile: false },
];

function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }
function ri(min, max) { return Math.floor(min + Math.random() * (max - min)); }
function hex(bytes) {
  let s = "";
  for (let i = 0; i < bytes; i++) s += ((Math.random() * 256) | 0).toString(16).padStart(2, "0");
  return s;
}

export default function () {
  const ts = new Date().toISOString();
  const b = pick(BROWSERS);
  const sid = `sess-k6-${__VU}-${__ITER}-${ri(0, 1e6)}`;
  const meta = {
    app: { name: "angular-gateway", version: "0.0.1", environment: ENV_NAME },
    sdk: { name: "@grafana/faro-web-sdk", version: "1.0.0" },
    session: { id: sid },
    browser: { name: b.name, version: b.version, os: b.os, mobile: b.mobile },
    page: { url: `https://microservices-${ENV_NAME}.jenkins2026.nubenetes.com/` },
  };

  // Web Vitals (jittered, realistic-ish): LCP/FCP/TTFB/INP in ms, CLS unitless.
  const vLcp = ri(1200, 3800), vFcp = ri(800, 2400), vTtfb = ri(150, 1050), vInp = ri(80, 430);
  const vCls = (Math.random() * 0.25).toFixed(3);
  const nowNs = `${Math.floor(Date.now() / 1000)}000000000`;
  const startNs = `${Math.floor(Date.now() / 1000) - 1}000000000`;

  const beacon = {
    meta,
    logs: [{ message: "page loaded", level: "info", context: {}, timestamp: ts }],
    measurements: [{ type: "web-vitals", values: { lcp: vLcp, fcp: vFcp, ttfb: vTtfb, inp: vInp, cls: parseFloat(vCls) }, timestamp: ts }],
    traces: {
      resourceSpans: [{
        resource: { attributes: [
          { key: "service.name", value: { stringValue: "angular-gateway" } },
          { key: "deployment.environment", value: { stringValue: ENV_NAME } },
        ] },
        scopeSpans: [{
          scope: { name: "@grafana/faro-web-tracing" },
          spans: [{ traceId: hex(16), spanId: hex(8), name: "documentLoad", kind: 1, startTimeUnixNano: startNs, endTimeUnixNano: nowNs }],
        }],
      }],
    },
  };

  const res = http.post(FARO_URL, JSON.stringify(beacon), {
    headers: { "Content-Type": "application/json" },
    tags: { faro_kind: "session" },
  });
  const okBeacon = check(res, { "faro beacon accepted (2xx)": (r) => r.status === 202 || r.status === 200 });
  beaconsSent.add(1);
  if (okBeacon) { lcp.add(vLcp); fcp.add(vFcp); ttfb.add(vTtfb); inp.add(vInp); }
  else beaconsFailed.add(1);

  // A fraction of sessions also throw a JS exception.
  if (Math.random() < ERROR_RATE) {
    const exc = {
      meta,
      exceptions: [{
        type: "TypeError",
        value: "Cannot read properties of undefined (reading 'data')",
        timestamp: ts,
        stacktrace: { frames: [{ filename: "main.js", function: "render", lineno: ri(1, 500) }] },
      }],
    };
    const er = http.post(FARO_URL, JSON.stringify(exc), { headers: { "Content-Type": "application/json" }, tags: { faro_kind: "exception" } });
    check(er, { "faro exception accepted (2xx)": (r) => r.status === 202 || r.status === 200 });
    exceptionsSent.add(1);
  }

  if (DEBUG) console.log(`[rum] vu=${__VU} iter=${__ITER} browser=${b.name}/${b.os} lcp=${vLcp} status=${res.status}`);
}

export function handleSummary(data) {
  const m = data.metrics || {};
  const val = (n, f, d = 0) => (m[n] && m[n].values && m[n].values[f] != null ? m[n].values[f] : d);
  const summary = {
    test: "faro-rum",
    env: ENV_NAME,
    faro_url: FARO_URL,
    beacons_sent: val("rum_beacons_sent", "count"),
    beacons_failed: val("rum_beacons_failed", "count"),
    exceptions_sent: val("rum_exceptions_sent", "count"),
    beacon_post_p95_ms: Math.round(val("http_req_duration", "p(95)")),
    web_vitals_p95: { lcp: Math.round(val("rum_web_vital_lcp_ms", "p(95)")), inp: Math.round(val("rum_web_vital_inp_ms", "p(95)")) },
  };
  return {
    "k6-summary.json": JSON.stringify(summary, null, 2),
    stdout: `\nFaro RUM: sent ${summary.beacons_sent} session beacons (${summary.exceptions_sent} with JS errors) to ${FARO_URL} as env=${ENV_NAME}; beacon POST p95 ${summary.beacon_post_p95_ms}ms.\n`,
  };
}

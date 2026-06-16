// =============================================================================
// Microservices Grafana observability smoke test (k6).
//
// NOT a load/stress test: a handful of virtual users (K6_VUS, default 4) each
// run a few iterations (K6_ITERATIONS, default 12, shared across all VUs) of a
// simulated session against the in-cluster Services in TARGET_NAMESPACE.
// =============================================================================

import http from 'k6/http';
import { check, sleep } from 'k6';

const NAMESPACE = __ENV.TARGET_NAMESPACE || 'microservices';
const TARGET_URL = __ENV.TARGET_URL;

function svcUrl(name, port, path = '') {
  if (TARGET_URL) {
    return `${TARGET_URL}${path}`;
  }
  return `http://${name}.${NAMESPACE}.svc.cluster.local:${port}${path}`;
}

const API_GATEWAY = svcUrl('gateway', 8080);
const MICROSERVICE = svcUrl('jhipstersamplemicroservice', 8081);

export const options = {
  vus: Number(__ENV.K6_VUS || 4),
  iterations: Number(__ENV.K6_ITERATIONS || 12),
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<3000'],
  },
};

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

export default function () {
  const traceparent = newTraceparent();
  console.log(`[microservices-smoke] iteration trace_id=${traceparent.split('-')[1]}`);

  // 1. Gateway UI landing page
  get(`${API_GATEWAY}/`, traceparent, 'gateway-ui-root');
  sleep(0.3);

  // 2. Gateway health check
  get(`${API_GATEWAY}/management/health`, traceparent, 'gateway-health');
  sleep(0.3);

  // 3. Microservice health check directly (if in-cluster)
  if (!TARGET_URL) {
    get(`${MICROSERVICE}/management/health`, traceparent, 'microservice-health');
    sleep(0.3);
  }

  // 4. Microservice health check via Gateway proxy routing (Option A verification)
  get(`${API_GATEWAY}/services/jhipstersamplemicroservice/management/health`, traceparent, 'gateway-proxy-microservice-health');
  sleep(0.3);
}

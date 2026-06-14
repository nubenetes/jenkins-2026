// =============================================================================
// PetClinic Grafana observability smoke test (k6).
//
// NOT a load/stress test: a handful of virtual users (K6_VUS, default 4) each
// run a few iterations (K6_ITERATIONS, default 12, shared across all VUs) of a
// simulated "owner browses PetClinic" session against the in-cluster Services
// in TARGET_NAMESPACE (the namespace one of the stable/-develop PetClinic
// pipelines just deployed to - petclinic or petclinic-develop).
//
// Every request in an iteration carries the same W3C `traceparent` header
// (generated per-iteration below). The OTel Java agent injected by
// helm/petclinic/templates/instrumentation.yaml has the `tracecontext`
// propagator enabled and a parentbased_traceidratio(1.0) sampler, so it picks
// up this header and continues the trace - meaning every service touched by
// one iteration shows up as one trace in Tempo, with its logs (trace_id
// injected into the MDC) and metrics correlatable in Grafana. The generated
// trace_id is logged so it can be pasted straight into Tempo's trace search.
//
// Run via jenkins/pipelines/Jenkinsfile.petclinic-k6-smoke /
// vars/petclinicK6Smoke.groovy, which also point k6's own `-o opentelemetry`
// metrics output at the same otel-collector-gateway, so the test's client-side
// request metrics land in Grafana Cloud alongside the application telemetry.
// =============================================================================

import http from 'k6/http';
import { check, sleep } from 'k6';

const NAMESPACE = __ENV.TARGET_NAMESPACE || 'petclinic';

// genai-service's pipeline (and therefore its deployed image) is disabled
// without a real OPENAI_API_KEY (see config/config.yaml
// petclinic.genaiServiceEnabled) - skip it entirely unless explicitly enabled,
// to avoid failing on a service that may not even be running.
const GENAI_ENABLED = (__ENV.GENAI_SERVICE_ENABLED || 'false').toLowerCase() === 'true';

function svcUrl(name, port) {
  return `http://${name}.${NAMESPACE}.svc.cluster.local:${port}`;
}

const API_GATEWAY = svcUrl('api-gateway', 8080);
const CONFIG_SERVER = svcUrl('config-server', 8888);
const DISCOVERY_SERVER = svcUrl('discovery-server', 8761);
const ADMIN_SERVER = svcUrl('admin-server', 9090);
const GENAI_SERVICE = svcUrl('genai-service', 8084);
const ANGULAR = svcUrl('petclinic-angular', 8080);

// Default owners 1-3 exist in spring-petclinic-microservices' seed data.
const OWNER_IDS = [1, 2, 3];

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

// Builds a sampled W3C traceparent header (https://www.w3.org/TR/trace-context/)
// with a fresh random trace-id/parent-id, so the receiving OTel Java agent
// starts a new trace rooted at this "request".
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
  console.log(`[petclinic-smoke] iteration trace_id=${traceparent.split('-')[1]}`);

  // Platform/infrastructure services - not reachable via api-gateway, hit
  // their actuator health endpoints directly.
  get(`${CONFIG_SERVER}/actuator/health`, traceparent, 'config-server-health');
  sleep(0.2);
  get(`${DISCOVERY_SERVER}/actuator/health`, traceparent, 'discovery-server-health');
  sleep(0.2);
  get(`${ADMIN_SERVER}/actuator/health`, traceparent, 'admin-server-health');
  sleep(0.2);

  if (GENAI_ENABLED) {
    get(`${GENAI_SERVICE}/actuator/health`, traceparent, 'genai-service-health');
    sleep(0.2);
  }

  // Angular UI - serves the SPA shell.
  get(`${ANGULAR}/`, traceparent, 'petclinic-angular-root');
  sleep(0.3);

  // "Owner browses PetClinic" journey through api-gateway, exercising
  // customers-service, vets-service and visits-service (and the gateway's
  // own owner+visits aggregation).
  get(`${API_GATEWAY}/api/vet/vets`, traceparent, 'gateway-vets');
  sleep(0.3);

  get(`${API_GATEWAY}/api/customer/petTypes`, traceparent, 'gateway-pet-types');
  sleep(0.3);

  get(`${API_GATEWAY}/api/customer/owners`, traceparent, 'gateway-owners-list');
  sleep(0.3);

  const ownerId = OWNER_IDS[Math.floor(Math.random() * OWNER_IDS.length)];
  get(`${API_GATEWAY}/api/customer/owners/${ownerId}`, traceparent, 'gateway-owner-details');
  sleep(0.3);

  // api-gateway's own /api/gateway/owners/{id} aggregates customers-service +
  // visits-service in a single call.
  get(`${API_GATEWAY}/api/gateway/owners/${ownerId}`, traceparent, 'gateway-owner-visits-aggregate');
  sleep(0.3);

  get(`${API_GATEWAY}/api/visit/pets/visits?petId=1&petId=2`, traceparent, 'gateway-visits');
  sleep(0.3);
}

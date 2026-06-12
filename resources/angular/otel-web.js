/**
 * Minimal browser-side OpenTelemetry RUM for the PetClinic Angular UI.
 *
 * Injected into every HTML page via nginx `sub_filter` (see nginx.conf).
 * This is a small, dependency-free implementation suitable for a PoC; for
 * production use, replace with @opentelemetry/sdk-trace-web +
 * @opentelemetry/instrumentation-fetch / instrumentation-document-load.
 *
 * What it does:
 *  1. Generates a W3C trace context (traceId/spanId) for the page load and
 *     exports a "page_load" span using Navigation Timing.
 *  2. Patches window.fetch so calls to same-origin /api/* (proxied to
 *     api-gateway, see nginx.conf) carry a `traceparent` header, linking the
 *     browser trace to the backend trace produced by the OTel Java agent -
 *     this is the metrics/traces/logs <-> frontend correlation point.
 *  3. Exports spans as OTLP/HTTP JSON to /otel/ (proxied to
 *     otel-collector-gateway.observability.svc:4318), same-origin so no
 *     CORS configuration is required.
 */
(function () {
  var OTLP_ENDPOINT = '/otel/v1/traces';
  var SERVICE_NAME = 'petclinic-angular-web';

  function randomHex(bytes) {
    var arr = new Uint8Array(bytes);
    (window.crypto || window.msCrypto).getRandomValues(arr);
    return Array.prototype.map.call(arr, function (b) {
      return ('0' + b.toString(16)).slice(-2);
    }).join('');
  }

  var traceId = randomHex(16); // 32 hex chars
  var pageLoadSpanId = randomHex(8); // 16 hex chars

  function exportSpans(spans) {
    var body = JSON.stringify({
      resourceSpans: [{
        resource: {
          attributes: [
            { key: 'service.name', value: { stringValue: SERVICE_NAME } },
            { key: 'service.namespace', value: { stringValue: 'jenkins-2026' } }
          ]
        },
        scopeSpans: [{
          scope: { name: 'otel-web.js', version: '0.1.0' },
          spans: spans
        }]
      }]
    });
    try {
      if (navigator.sendBeacon) {
        navigator.sendBeacon(OTLP_ENDPOINT, new Blob([body], { type: 'application/json' }));
      } else {
        fetch(OTLP_ENDPOINT, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: body, keepalive: true });
      }
    } catch (e) {
      // Swallow telemetry errors - never break the app.
      console.debug('otel-web: export failed', e);
    }
  }

  function exportPageLoadSpan() {
    var t = performance.timing;
    var start = t.navigationStart || t.fetchStart || Date.now();
    var end = t.loadEventEnd || Date.now();
    if (end <= start) { end = start + 1; }

    exportSpans([{
      traceId: traceId,
      spanId: pageLoadSpanId,
      name: 'document_load ' + location.pathname,
      kind: 1, // SPAN_KIND_INTERNAL
      startTimeUnixNano: String(start * 1e6),
      endTimeUnixNano: String(end * 1e6),
      attributes: [
        { key: 'http.url', value: { stringValue: location.href } },
        { key: 'browser.language', value: { stringValue: navigator.language } }
      ]
    }]);
  }

  // Propagate trace context to the backend on every /api/* call, and export
  // a client-side span for each request so it shows up alongside the
  // backend spans it caused.
  var originalFetch = window.fetch;
  window.fetch = function (input, init) {
    var url = (typeof input === 'string') ? input : input.url;
    init = init || {};

    if (url.indexOf('/api/') === 0 || url.indexOf(location.origin + '/api/') === 0) {
      var spanId = randomHex(8);
      var traceparent = '00-' + traceId + '-' + spanId + '-01';
      var headers = new Headers(init.headers || {});
      headers.set('traceparent', traceparent);
      init = Object.assign({}, init, { headers: headers });

      var start = Date.now();
      return originalFetch(input, init).then(function (resp) {
        exportSpans([{
          traceId: traceId,
          spanId: spanId,
          name: 'fetch ' + url,
          kind: 3, // SPAN_KIND_CLIENT
          startTimeUnixNano: String(start * 1e6),
          endTimeUnixNano: String(Date.now() * 1e6),
          attributes: [
            { key: 'http.url', value: { stringValue: url } },
            { key: 'http.status_code', value: { intValue: resp.status } }
          ]
        }]);
        return resp;
      });
    }

    return originalFetch(input, init);
  };

  if (document.readyState === 'complete') {
    exportPageLoadSpan();
  } else {
    window.addEventListener('load', function () {
      // loadEventEnd is only populated after the load event finishes.
      setTimeout(exportPageLoadSpan, 0);
    });
  }
})();

#!/usr/bin/env bash
set -Eeuo pipefail

NAMESPACE="${NAMESPACE:-elastic-stack}"
STACK_NAME="${STACK_NAME:-elastic-stack}"
INDEX_NAME="${INDEX_NAME:-demo-index}"
ES_PORT="${ES_PORT:-19200}"
KB_PORT="${KB_PORT:-15601}"
EXPORTER_PORT="${EXPORTER_PORT:-19114}"
ES_API_RETRY_ATTEMPTS="${ES_API_RETRY_ATTEMPTS:-60}"
ES_API_RETRY_INTERVAL_SECONDS="${ES_API_RETRY_INTERVAL_SECONDS:-2}"
ES_SERVICE_DNS="${ES_SERVICE_DNS:-${STACK_NAME}-es-http.${NAMESPACE}.svc}"
KB_SERVICE_DNS="${KB_SERVICE_DNS:-${STACK_NAME}-kb-http.${NAMESPACE}.svc}"

log() { printf '[verify] %s\n' "$*"; }
fail() { printf '[verify] ERROR: %s\n' "$*" >&2; exit 1; }

for command in kubectl curl base64 grep; do
  command -v "$command" >/dev/null 2>&1 || fail "Missing command: ${command}"
done

tmp_dir="$(mktemp -d)"
pids=()
cleanup() {
  for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

elastic_password="$(kubectl -n "${NAMESPACE}" get secret "${STACK_NAME}-es-elastic-user" -o go-template='{{.data.elastic | base64decode}}')"
kubectl -n "${NAMESPACE}" get secret "${STACK_NAME}-es-http-certs-public" -o jsonpath='{.data.tls\.crt}' | base64 -d > "${tmp_dir}/es-ca.crt"
kubectl -n "${NAMESPACE}" get secret "${STACK_NAME}-kb-http-certs-public" -o jsonpath='{.data.tls\.crt}' | base64 -d > "${tmp_dir}/kb-ca.crt"

kubectl -n "${NAMESPACE}" port-forward "service/${STACK_NAME}-es-http" "${ES_PORT}:9200" --address 127.0.0.1 >"${tmp_dir}/es-pf.log" 2>&1 & pids+=("$!")
kubectl -n "${NAMESPACE}" port-forward "service/${STACK_NAME}-kb-http" "${KB_PORT}:5601" --address 127.0.0.1 >"${tmp_dir}/kb-pf.log" 2>&1 & pids+=("$!")
kubectl -n "${NAMESPACE}" port-forward "service/${STACK_NAME}-exporter" "${EXPORTER_PORT}:9114" --address 127.0.0.1 >"${tmp_dir}/exporter-pf.log" 2>&1 & pids+=("$!")

es_base_url="https://${ES_SERVICE_DNS}:${ES_PORT}"
kb_base_url="https://${KB_SERVICE_DNS}:${KB_PORT}"
es_resolve="${ES_SERVICE_DNS}:${ES_PORT}:127.0.0.1"
kb_resolve="${KB_SERVICE_DNS}:${KB_PORT}:127.0.0.1"
es_curl_args=(--silent --show-error --fail --cacert "${tmp_dir}/es-ca.crt" --resolve "${es_resolve}" --noproxy "${ES_SERVICE_DNS}" --user "elastic:${elastic_password}")
kb_curl_args=(--silent --show-error --fail --cacert "${tmp_dir}/kb-ca.crt" --resolve "${kb_resolve}" --noproxy "${KB_SERVICE_DNS}" --user "elastic:${elastic_password}")

es_ready=false
es_probe_error="${tmp_dir}/es-probe-error.log"
for attempt in $(seq 1 "${ES_API_RETRY_ATTEMPTS}"); do
  if curl "${es_curl_args[@]}" "${es_base_url}/" >/dev/null 2>"${es_probe_error}"; then
    es_ready=true
    break
  fi
  log "Elasticsearch API is not reachable yet (attempt ${attempt}/${ES_API_RETRY_ATTEMPTS}); retrying"
  sleep "${ES_API_RETRY_INTERVAL_SECONDS}"
done
if [[ "${es_ready}" != "true" ]]; then
  [[ ! -s "${es_probe_error}" ]] || sed 's/^/[curl] /' "${es_probe_error}" >&2
  fail "Elasticsearch API did not become reachable after ${ES_API_RETRY_ATTEMPTS} attempts"
fi

log "Creating single-node test index with zero replicas"
index_status="$(curl --silent --show-error \
  --cacert "${tmp_dir}/es-ca.crt" \
  --resolve "${es_resolve}" \
  --noproxy "${ES_SERVICE_DNS}" \
  --user "elastic:${elastic_password}" \
  --output /dev/null --write-out '%{http_code}' \
  "${es_base_url}/${INDEX_NAME}")"
if [[ "${index_status}" == "404" ]]; then
  curl "${es_curl_args[@]}" \
    -H 'Content-Type: application/json' -X PUT "${es_base_url}/${INDEX_NAME}" \
    --data-binary '{"settings":{"number_of_replicas":0}}' >/dev/null
elif [[ "${index_status}" != "200" ]]; then
  fail "Unexpected index status code: ${index_status}"
fi

log "Indexing and searching a test document"
curl "${es_curl_args[@]}" \
  -H 'Content-Type: application/json' -X PUT "${es_base_url}/${INDEX_NAME}/_doc/1?refresh=wait_for" \
  --data-binary '{"message":"hello from the Bitnami-free ECK deployment"}' >/dev/null
search_result="$(curl "${es_curl_args[@]}" "${es_base_url}/${INDEX_NAME}/_search?q=_id:1")"
grep -q 'hello from the Bitnami-free ECK deployment' <<<"${search_result}" || fail "Test document was not found"

health=""
for _ in $(seq 1 30); do
  health="$(curl "${es_curl_args[@]}" "${es_base_url}/_cluster/health")"
  grep -q '"status":"green"' <<<"${health}" && break
  sleep 2
done
grep -q '"status":"green"' <<<"${health}" || fail "Cluster health is not green: ${health}"

log "Checking Kibana status"
curl "${kb_curl_args[@]}" "${kb_base_url}/api/status" | grep -q 'available' || fail "Kibana is not available"

log "Checking exporter health endpoint"
curl --silent --show-error --fail "http://127.0.0.1:${EXPORTER_PORT}/healthz" >/dev/null || fail "Exporter health endpoint failed"

log "Checking exporter metrics"
exporter_metrics_file="${tmp_dir}/exporter-metrics.txt"
exporter_metrics_error="${tmp_dir}/exporter-metrics-error.log"
if ! curl --silent --show-error --fail \
  "http://127.0.0.1:${EXPORTER_PORT}/metrics" \
  --output "${exporter_metrics_file}" 2>"${exporter_metrics_error}"; then
  [[ ! -s "${exporter_metrics_error}" ]] || sed 's/^/[curl] /' "${exporter_metrics_error}" >&2
  fail "Exporter /metrics endpoint is not reachable at http://127.0.0.1:${EXPORTER_PORT}/metrics"
fi
if ! grep -q '^elasticsearch_' "${exporter_metrics_file}"; then
  fail "Exporter /metrics endpoint is reachable but returned no elasticsearch_* metrics"
fi

unset elastic_password search_result health es_curl_args kb_curl_args
log "All integration checks passed"

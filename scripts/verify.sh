#!/usr/bin/env bash
set -Eeuo pipefail

NAMESPACE="${NAMESPACE:-elastic-stack}"
STACK_NAME="${STACK_NAME:-elastic-stack}"
INDEX_NAME="${INDEX_NAME:-bitnami-free-demo}"
ES_PORT="${ES_PORT:-19200}"
KB_PORT="${KB_PORT:-15601}"
EXPORTER_PORT="${EXPORTER_PORT:-19114}"

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

es_ready=false
for _ in $(seq 1 60); do
  if curl --silent --fail --cacert "${tmp_dir}/es-ca.crt" -u "elastic:${elastic_password}" "https://127.0.0.1:${ES_PORT}" >/dev/null; then
    es_ready=true
    break
  fi
  sleep 2
done
[[ "${es_ready}" == "true" ]] || fail "Elasticsearch API did not become reachable"

log "Creating single-node test index with zero replicas"
index_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --cacert "${tmp_dir}/es-ca.crt" -u "elastic:${elastic_password}" "https://127.0.0.1:${ES_PORT}/${INDEX_NAME}")"
if [[ "${index_status}" == "404" ]]; then
  curl --silent --show-error --fail --cacert "${tmp_dir}/es-ca.crt" -u "elastic:${elastic_password}" \
    -H 'Content-Type: application/json' -X PUT "https://127.0.0.1:${ES_PORT}/${INDEX_NAME}" \
    --data-binary '{"settings":{"number_of_replicas":0}}' >/dev/null
elif [[ "${index_status}" != "200" ]]; then
  fail "Unexpected index status code: ${index_status}"
fi

log "Indexing and searching a test document"
curl --silent --show-error --fail --cacert "${tmp_dir}/es-ca.crt" -u "elastic:${elastic_password}" \
  -H 'Content-Type: application/json' -X PUT "https://127.0.0.1:${ES_PORT}/${INDEX_NAME}/_doc/1?refresh=wait_for" \
  --data-binary '{"message":"hello from the Bitnami-free ECK deployment"}' >/dev/null
search_result="$(curl --silent --show-error --fail --cacert "${tmp_dir}/es-ca.crt" -u "elastic:${elastic_password}" "https://127.0.0.1:${ES_PORT}/${INDEX_NAME}/_search?q=_id:1")"
grep -q 'hello from the Bitnami-free ECK deployment' <<<"${search_result}" || fail "Test document was not found"

health=""
for _ in $(seq 1 30); do
  health="$(curl --silent --show-error --fail --cacert "${tmp_dir}/es-ca.crt" -u "elastic:${elastic_password}" "https://127.0.0.1:${ES_PORT}/_cluster/health")"
  grep -q '"status":"green"' <<<"${health}" && break
  sleep 2
done
grep -q '"status":"green"' <<<"${health}" || fail "Cluster health is not green: ${health}"

log "Checking Kibana status"
curl --silent --show-error --fail --cacert "${tmp_dir}/kb-ca.crt" -u "elastic:${elastic_password}" "https://127.0.0.1:${KB_PORT}/api/status" | grep -q 'available' || fail "Kibana is not available"

log "Checking exporter metrics"
curl --silent --show-error --fail "http://127.0.0.1:${EXPORTER_PORT}/metrics" | grep -q '^elasticsearch_' || fail "Exporter did not return Elasticsearch metrics"

unset elastic_password search_result health
log "All integration checks passed"

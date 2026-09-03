#!/usr/bin/env bash
set -Eeuo pipefail

NAMESPACE="${NAMESPACE:-elastic-stack}"
STACK_NAME="${STACK_NAME:-elastic-stack}"
EXPORTER_USER="${EXPORTER_USER:-elasticsearch_exporter}"
EXPORTER_SECRET="${EXPORTER_SECRET:-elasticsearch-exporter-credentials}"
LOCAL_PORT="${LOCAL_PORT:-19200}"

log() { printf '[metrics-user] %s\n' "$*"; }
fail() { printf '[metrics-user] ERROR: %s\n' "$*" >&2; exit 1; }

for command in kubectl curl openssl base64; do
  command -v "$command" >/dev/null 2>&1 || fail "Missing command: ${command}"
done

tmp_dir="$(mktemp -d)"
port_forward_pid=""
cleanup() {
  [[ -n "${port_forward_pid}" ]] && kill "${port_forward_pid}" 2>/dev/null || true
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

elastic_password="$(kubectl -n "${NAMESPACE}" get secret "${STACK_NAME}-es-elastic-user" -o go-template='{{.data.elastic | base64decode}}')"
kubectl -n "${NAMESPACE}" get secret "${STACK_NAME}-es-http-certs-public" -o jsonpath='{.data.tls\.crt}' | base64 -d > "${tmp_dir}/ca.crt"

kubectl -n "${NAMESPACE}" port-forward "service/${STACK_NAME}-es-http" "${LOCAL_PORT}:9200" --address 127.0.0.1 >"${tmp_dir}/port-forward.log" 2>&1 &
port_forward_pid=$!

es_ready=false
for _ in $(seq 1 30); do
  if curl --silent --fail --cacert "${tmp_dir}/ca.crt" -u "elastic:${elastic_password}" "https://127.0.0.1:${LOCAL_PORT}" >/dev/null; then
    es_ready=true
    break
  fi
  sleep 2
done
[[ "${es_ready}" == "true" ]] || fail "Elasticsearch API did not become reachable; see ${tmp_dir}/port-forward.log before cleanup"

if kubectl -n "${NAMESPACE}" get secret "${EXPORTER_SECRET}" >/dev/null 2>&1; then
  exporter_password="$(kubectl -n "${NAMESPACE}" get secret "${EXPORTER_SECRET}" -o go-template='{{.data.password | base64decode}}')"
else
  exporter_password="$(openssl rand -hex 20)"
fi
[[ "${#exporter_password}" -eq 40 ]] || fail "Could not generate exporter password"

log "Creating least-privilege exporter role"
curl --silent --show-error --fail \
  --cacert "${tmp_dir}/ca.crt" \
  -u "elastic:${elastic_password}" \
  -H 'Content-Type: application/json' \
  -X PUT "https://127.0.0.1:${LOCAL_PORT}/_security/role/elasticsearch_exporter" \
  --data-binary '{"cluster":["monitor"],"indices":[{"names":["*"],"privileges":["monitor"]}]}' >/dev/null

user_payload="$(printf '{"password":"%s","roles":["elasticsearch_exporter"],"full_name":"Prometheus Elasticsearch Exporter"}' "${exporter_password}")"
log "Creating exporter user"
curl --silent --show-error --fail \
  --cacert "${tmp_dir}/ca.crt" \
  -u "elastic:${elastic_password}" \
  -H 'Content-Type: application/json' \
  -X PUT "https://127.0.0.1:${LOCAL_PORT}/_security/user/${EXPORTER_USER}" \
  --data-binary "${user_payload}" >/dev/null

kubectl -n "${NAMESPACE}" create secret generic "${EXPORTER_SECRET}" \
  --from-literal=username="${EXPORTER_USER}" \
  --from-literal=password="${exporter_password}" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

unset elastic_password exporter_password user_payload
log "Exporter credentials are stored only in Kubernetes Secret ${NAMESPACE}/${EXPORTER_SECRET}"

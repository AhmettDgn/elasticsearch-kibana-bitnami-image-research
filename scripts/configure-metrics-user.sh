#!/usr/bin/env bash
set -Eeuo pipefail

NAMESPACE="${NAMESPACE:-elastic-stack}"
STACK_NAME="${STACK_NAME:-elastic-stack}"
EXPORTER_USER="${EXPORTER_USER:-elasticsearch_exporter}"
EXPORTER_SECRET="${EXPORTER_SECRET:-elasticsearch-exporter-credentials}"
LOCAL_PORT="${LOCAL_PORT:-19200}"
ES_SERVICE_DNS="${ES_SERVICE_DNS:-${STACK_NAME}-es-http.${NAMESPACE}.svc}"
API_RETRY_ATTEMPTS="${API_RETRY_ATTEMPTS:-30}"
RETRY_INTERVAL_SECONDS="${RETRY_INTERVAL_SECONDS:-2}"
CURL_CONNECT_TIMEOUT_SECONDS="${CURL_CONNECT_TIMEOUT_SECONDS:-3}"
CURL_MAX_TIME_SECONDS="${CURL_MAX_TIME_SECONDS:-10}"

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

print_connection_diagnostics() {
  printf '[metrics-user] Port-forward log:\n' >&2
  if [[ -s "${tmp_dir}/port-forward.log" ]]; then
    sed 's/^/[port-forward] /' "${tmp_dir}/port-forward.log" >&2
  else
    printf '[port-forward] <empty>\n' >&2
  fi
  if [[ -s "${tmp_dir}/curl-error.log" ]]; then
    printf '[metrics-user] Last curl error:\n' >&2
    sed 's/^/[curl] /' "${tmp_dir}/curl-error.log" >&2
  fi
}

elastic_password="$(kubectl -n "${NAMESPACE}" get secret "${STACK_NAME}-es-elastic-user" -o go-template='{{.data.elastic | base64decode}}')"
kubectl -n "${NAMESPACE}" get secret "${STACK_NAME}-es-http-certs-public" -o jsonpath='{.data.tls\.crt}' | base64 -d > "${tmp_dir}/ca.crt"

kubectl -n "${NAMESPACE}" port-forward "service/${STACK_NAME}-es-http" "${LOCAL_PORT}:9200" --address 127.0.0.1 >"${tmp_dir}/port-forward.log" 2>&1 &
port_forward_pid=$!

es_base_url="https://${ES_SERVICE_DNS}:${LOCAL_PORT}"
es_resolve="${ES_SERVICE_DNS}:${LOCAL_PORT}:127.0.0.1"
curl_common_args=(
  --silent
  --show-error
  --fail
  --cacert "${tmp_dir}/ca.crt"
  --resolve "${es_resolve}"
  --noproxy "${ES_SERVICE_DNS}"
  --connect-timeout "${CURL_CONNECT_TIMEOUT_SECONDS}"
  --max-time "${CURL_MAX_TIME_SECONDS}"
  --user "elastic:${elastic_password}"
)

es_ready=false
for attempt in $(seq 1 "${API_RETRY_ATTEMPTS}"); do
  if ! kill -0 "${port_forward_pid}" 2>/dev/null; then
    print_connection_diagnostics
    fail "Elasticsearch port-forward process exited before the API became reachable"
  fi
  if curl "${curl_common_args[@]}" "${es_base_url}/" >/dev/null 2>"${tmp_dir}/curl-error.log"; then
    es_ready=true
    break
  fi
  printf '[metrics-user] Elasticsearch API probe %s/%s failed:\n' "${attempt}" "${API_RETRY_ATTEMPTS}" >&2
  sed 's/^/[curl] /' "${tmp_dir}/curl-error.log" >&2
  sleep "${RETRY_INTERVAL_SECONDS}"
done
if [[ "${es_ready}" != "true" ]]; then
  print_connection_diagnostics
  fail "Elasticsearch API did not become reachable through the TLS-verified service DNS name"
fi

if kubectl -n "${NAMESPACE}" get secret "${EXPORTER_SECRET}" >/dev/null 2>&1; then
  exporter_password="$(kubectl -n "${NAMESPACE}" get secret "${EXPORTER_SECRET}" -o go-template='{{.data.password | base64decode}}')"
else
  exporter_password="$(openssl rand -hex 20)"
fi
[[ "${#exporter_password}" -eq 40 ]] || fail "Could not generate exporter password"

log "Creating least-privilege exporter role"
curl --silent --show-error --fail \
  --cacert "${tmp_dir}/ca.crt" \
  --resolve "${es_resolve}" \
  --noproxy "${ES_SERVICE_DNS}" \
  --connect-timeout "${CURL_CONNECT_TIMEOUT_SECONDS}" \
  --max-time "${CURL_MAX_TIME_SECONDS}" \
  --user "elastic:${elastic_password}" \
  -H 'Content-Type: application/json' \
  -X PUT "${es_base_url}/_security/role/elasticsearch_exporter" \
  --data-binary '{"cluster":["monitor"],"indices":[{"names":["*"],"privileges":["monitor"]}]}' >/dev/null

user_payload="$(printf '{"password":"%s","roles":["elasticsearch_exporter"],"full_name":"Prometheus Elasticsearch Exporter"}' "${exporter_password}")"
log "Creating exporter user"
curl --silent --show-error --fail \
  --cacert "${tmp_dir}/ca.crt" \
  --resolve "${es_resolve}" \
  --noproxy "${ES_SERVICE_DNS}" \
  --connect-timeout "${CURL_CONNECT_TIMEOUT_SECONDS}" \
  --max-time "${CURL_MAX_TIME_SECONDS}" \
  --user "elastic:${elastic_password}" \
  -H 'Content-Type: application/json' \
  -X PUT "${es_base_url}/_security/user/${EXPORTER_USER}" \
  --data-binary "${user_payload}" >/dev/null

kubectl -n "${NAMESPACE}" create secret generic "${EXPORTER_SECRET}" \
  --from-literal=username="${EXPORTER_USER}" \
  --from-literal=password="${exporter_password}" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

unset elastic_password exporter_password user_payload curl_common_args
log "Exporter credentials are stored only in Kubernetes Secret ${NAMESPACE}/${EXPORTER_SECRET}"

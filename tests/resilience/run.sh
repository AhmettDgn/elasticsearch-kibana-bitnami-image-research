#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAMESPACE="${NAMESPACE:-elastic-stack}"
STACK_NAME="${STACK_NAME:-elastic-stack}"
INDEX_NAME="${INDEX_NAME:-demo-index}"
ES_PORT="${RESILIENCE_ES_PORT:-19201}"
ES_SERVICE_DNS="${ES_SERVICE_DNS:-${STACK_NAME}-es-http.${NAMESPACE}.svc}"
DEPLOY_SCRIPT="${DEPLOY_SCRIPT:-${ROOT_DIR}/scripts/deploy.sh}"
VERIFY_SCRIPT="${VERIFY_SCRIPT:-${ROOT_DIR}/scripts/verify.sh}"
POD_SELECTOR="elasticsearch.k8s.elastic.co/cluster-name=${STACK_NAME}"
POD_DISCOVERY_ATTEMPTS="${POD_DISCOVERY_ATTEMPTS:-60}"
POD_DISCOVERY_INTERVAL_SECONDS="${POD_DISCOVERY_INTERVAL_SECONDS:-2}"
POD_READY_TIMEOUT_SECONDS="${POD_READY_TIMEOUT_SECONDS:-600}"
CR_HEALTH_ATTEMPTS="${CR_HEALTH_ATTEMPTS:-300}"
CR_HEALTH_INTERVAL_SECONDS="${CR_HEALTH_INTERVAL_SECONDS:-2}"
API_RETRY_ATTEMPTS="${API_RETRY_ATTEMPTS:-60}"
API_RETRY_INTERVAL_SECONDS="${API_RETRY_INTERVAL_SECONDS:-2}"

tmp_dir="$(mktemp -d)"
port_forward_pid=""
diagnostics_printed=false

log() { printf '[resilience] %s\n' "$*"; }

stop_port_forward() {
  if [[ -n "${port_forward_pid}" ]]; then
    kill "${port_forward_pid}" 2>/dev/null || true
    wait "${port_forward_pid}" 2>/dev/null || true
    port_forward_pid=""
  fi
}

cleanup() {
  stop_port_forward
  rm -rf "${tmp_dir}"
}

diagnostics() {
  [[ "${diagnostics_printed}" == "false" ]] || return 0
  diagnostics_printed=true
  set +e
  printf '\n[resilience] ===== automatic diagnostics =====\n' >&2
  kubectl get elasticsearch,pods,pvc -n "${NAMESPACE}" -o wide >&2
  kubectl get events -n "${NAMESPACE}" --sort-by=.lastTimestamp >&2
  kubectl describe elasticsearch "${STACK_NAME}" -n "${NAMESPACE}" >&2
  printf '[resilience] ===== end diagnostics =====\n' >&2
  set -e
}

fail() {
  printf '[resilience] ERROR: %s\n' "$*" >&2
  diagnostics
  exit 1
}

on_error() {
  local exit_code="$1"
  local line_number="$2"
  trap - ERR
  printf '[resilience] ERROR: command failed at line %s (exit %s)\n' "${line_number}" "${exit_code}" >&2
  diagnostics
  exit "${exit_code}"
}

trap cleanup EXIT
trap 'on_error $? $LINENO' ERR

for command in kubectl curl base64 grep; do
  command -v "${command}" >/dev/null 2>&1 || fail "Missing command: ${command}"
done

start_port_forward() {
  local stage="$1"
  stop_port_forward
  : > "${tmp_dir}/port-forward-${stage}.log"
  kubectl -n "${NAMESPACE}" port-forward "service/${STACK_NAME}-es-http" \
    "${ES_PORT}:9200" --address 127.0.0.1 \
    >"${tmp_dir}/port-forward-${stage}.log" 2>&1 &
  port_forward_pid=$!
}

wait_for_api() {
  local stage="$1"
  local error_file="${tmp_dir}/api-${stage}.log"
  local attempt

  for attempt in $(seq 1 "${API_RETRY_ATTEMPTS}"); do
    if ! kill -0 "${port_forward_pid}" 2>/dev/null; then
      [[ ! -s "${tmp_dir}/port-forward-${stage}.log" ]] || sed 's/^/[port-forward] /' "${tmp_dir}/port-forward-${stage}.log" >&2
      fail "Elasticsearch port-forward exited during ${stage} API readiness"
    fi
    if curl "${es_curl_args[@]}" "${es_base_url}/" >/dev/null 2>"${error_file}"; then
      log "Elasticsearch API is reachable (${stage})"
      return 0
    fi
    log "Waiting for Elasticsearch API (${stage}, ${attempt}/${API_RETRY_ATTEMPTS})"
    sleep "${API_RETRY_INTERVAL_SECONDS}"
  done

  [[ ! -s "${error_file}" ]] || sed 's/^/[curl] /' "${error_file}" >&2
  [[ ! -s "${tmp_dir}/port-forward-${stage}.log" ]] || sed 's/^/[port-forward] /' "${tmp_dir}/port-forward-${stage}.log" >&2
  fail "Elasticsearch API did not become reachable during ${stage}"
}

assert_document_exists() {
  local stage="$1"
  local response_file="${tmp_dir}/document-${stage}.json"
  local error_file="${tmp_dir}/document-${stage}.log"

  if ! curl "${es_curl_args[@]}" \
    "${es_base_url}/${INDEX_NAME}/_doc/1" \
    --output "${response_file}" 2>"${error_file}"; then
    [[ ! -s "${error_file}" ]] || sed 's/^/[curl] /' "${error_file}" >&2
    fail "Could not read ${INDEX_NAME}/_doc/1 during ${stage}"
  fi
  if ! grep -Eq '"found"[[:space:]]*:[[:space:]]*true' "${response_file}"; then
    fail "Persisted document check failed during ${stage}: expected found=true for ${INDEX_NAME}/_doc/1"
  fi
  log "Document ${INDEX_NAME}/_doc/1 found=true (${stage})"
}

wait_for_recreated_pod() {
  local old_uid="$1"
  local attempt
  local pod_record=""
  local candidate_name=""
  local candidate_uid=""

  for attempt in $(seq 1 "${POD_DISCOVERY_ATTEMPTS}"); do
    pod_record="$(kubectl get pods -n "${NAMESPACE}" -l "${POD_SELECTOR}" \
      -o jsonpath='{.items[0].metadata.name}{"|"}{.items[0].metadata.uid}' 2>/dev/null || true)"
    IFS='|' read -r candidate_name candidate_uid <<<"${pod_record}"
    if [[ -n "${candidate_name}" && -n "${candidate_uid}" && "${candidate_uid}" != "${old_uid}" ]]; then
      printf '%s' "${candidate_name}"
      return 0
    fi
    log "Waiting for recreated Elasticsearch pod (${attempt}/${POD_DISCOVERY_ATTEMPTS})" >&2
    sleep "${POD_DISCOVERY_INTERVAL_SECONDS}"
  done
  return 1
}

wait_for_elasticsearch_cr() {
  local attempt
  local phase=""
  local health=""
  local state=""
  local previous_state=""

  for attempt in $(seq 1 "${CR_HEALTH_ATTEMPTS}"); do
    phase="$(kubectl get elasticsearch "${STACK_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    health="$(kubectl get elasticsearch "${STACK_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.health}' 2>/dev/null || true)"
    state="phase=${phase:-<empty>} health=${health:-<empty>}"
    if [[ "${state}" != "${previous_state}" ]]; then
      log "Elasticsearch ${state} after pod recreation"
      previous_state="${state}"
    fi
    if [[ "${phase}" == "Ready" && "${health}" == "green" ]]; then
      return 0
    fi
    sleep "${CR_HEALTH_INTERVAL_SECONDS}"
  done
  fail "Elasticsearch CR did not return to phase=Ready and health=green (last ${state})"
}

log 'Re-running the idempotent deployment'
"${DEPLOY_SCRIPT}"
"${VERIFY_SCRIPT}"

elastic_password="$(kubectl -n "${NAMESPACE}" get secret "${STACK_NAME}-es-elastic-user" -o go-template='{{.data.elastic | base64decode}}')"
kubectl -n "${NAMESPACE}" get secret "${STACK_NAME}-es-http-certs-public" \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > "${tmp_dir}/es-ca.crt"
es_base_url="https://${ES_SERVICE_DNS}:${ES_PORT}"
es_curl_args=(
  --silent --show-error --fail
  --cacert "${tmp_dir}/es-ca.crt"
  --resolve "${ES_SERVICE_DNS}:${ES_PORT}:127.0.0.1"
  --noproxy "${ES_SERVICE_DNS}"
  --user "elastic:${elastic_password}"
)

start_port_forward before-recreation
wait_for_api before-recreation
assert_document_exists before-recreation
stop_port_forward

old_pod_record="$(kubectl get pods -n "${NAMESPACE}" -l "${POD_SELECTOR}" \
  -o jsonpath='{.items[0].metadata.name}{"|"}{.items[0].metadata.uid}')"
IFS='|' read -r old_pod old_uid <<<"${old_pod_record}"
[[ -n "${old_pod}" && -n "${old_uid}" ]] || fail "Elasticsearch pod not found before recreation"

log "Recreating Elasticsearch pod ${old_pod}"
kubectl -n "${NAMESPACE}" delete pod "${old_pod}" --wait=true

new_pod="$(wait_for_recreated_pod "${old_uid}")" || fail "Recreated Elasticsearch pod did not appear"
log "Recreated Elasticsearch pod ${new_pod} appeared; waiting for Ready"
kubectl wait --for=condition=Ready "pod/${new_pod}" \
  -n "${NAMESPACE}" --timeout="${POD_READY_TIMEOUT_SECONDS}s"

wait_for_elasticsearch_cr

start_port_forward after-recreation
wait_for_api after-recreation
assert_document_exists after-recreation
stop_port_forward

unset elastic_password es_curl_args
log 'Persistence and idempotency checks passed'

#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-elastic-stack}"
OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE:-elastic-system}"
STACK_NAME="${STACK_NAME:-elastic-stack}"
ECK_VERSION="${ECK_VERSION:-3.5.0}"
VALUES_FILE="${VALUES_FILE:-${ROOT_DIR}/helm-values/non-bitnami-values.yaml}"
METRICS_CONFIGURE_SCRIPT="${METRICS_CONFIGURE_SCRIPT:-${ROOT_DIR}/scripts/configure-metrics-user.sh}"
CR_TIMEOUT_SECONDS="${CR_TIMEOUT_SECONDS:-180}"
HEALTH_TIMEOUT_SECONDS="${HEALTH_TIMEOUT_SECONDS:-900}"
POD_DISCOVERY_TIMEOUT_SECONDS="${POD_DISCOVERY_TIMEOUT_SECONDS:-180}"
POD_READY_TIMEOUT_SECONDS="${POD_READY_TIMEOUT_SECONDS:-600}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-10}"
DIAGNOSTICS_ENABLED=false
DIAGNOSTICS_PRINTED=false
KIBANA_SELECTOR=""

log() { printf '[deploy] %s\n' "$*"; }
diagnostics() {
  [[ "${DIAGNOSTICS_ENABLED}" == "true" ]] || return 0
  [[ "${DIAGNOSTICS_PRINTED}" == "false" ]] || return 0
  DIAGNOSTICS_PRINTED=true

  set +e
  printf '\n[deploy] ===== automatic diagnostics =====\n' >&2
  kubectl get elasticsearch,kibana -n "${NAMESPACE}" >&2
  kubectl get pods,pvc,svc -n "${NAMESPACE}" -o wide >&2
  kubectl describe pods -n "${NAMESPACE}" >&2
  kubectl get events -n "${NAMESPACE}" --sort-by=.lastTimestamp >&2
  kubectl logs -n "${OPERATOR_NAMESPACE}" statefulset/elastic-operator --tail=150 >&2
  printf '[deploy] ===== end diagnostics =====\n' >&2
  set -e
}
fail() {
  printf '[deploy] ERROR: %s\n' "$*" >&2
  diagnostics
  exit 1
}
on_error() {
  local exit_code="$1"
  local line_number="$2"
  trap - ERR
  printf '[deploy] ERROR: command failed at line %s (exit %s)\n' "${line_number}" "${exit_code}" >&2
  diagnostics
  exit "${exit_code}"
}
trap 'on_error $? $LINENO' ERR

wait_for_resource() {
  local resource_type="$1"
  local resource_name="$2"
  local timeout_seconds="$3"
  local deadline=$((SECONDS + timeout_seconds))

  log "Waiting for ${resource_type}/${resource_name} to be created"
  while (( SECONDS < deadline )); do
    if kubectl get "${resource_type}" "${resource_name}" -n "${NAMESPACE}" >/dev/null 2>&1; then
      log "Found ${resource_type}/${resource_name}"
      return 0
    fi
    sleep "${POLL_INTERVAL_SECONDS}"
  done
  fail "Timed out after ${timeout_seconds}s waiting for ${resource_type}/${resource_name}"
}

wait_for_elasticsearch_health() {
  local deadline=$((SECONDS + HEALTH_TIMEOUT_SECONDS))
  local phase=""
  local health=""
  local previous_state=""
  local current_state=""

  log "Waiting up to ${HEALTH_TIMEOUT_SECONDS}s for Elasticsearch health=green"
  while (( SECONDS < deadline )); do
    phase="$(kubectl get elasticsearch "${STACK_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    health="$(kubectl get elasticsearch "${STACK_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.health}' 2>/dev/null || true)"
    current_state="phase=${phase:-<empty>} health=${health:-<empty>}"
    if [[ "${current_state}" != "${previous_state}" ]]; then
      log "Elasticsearch ${current_state}"
      previous_state="${current_state}"
    fi
    if [[ "${health}" == "green" ]]; then
      log "Elasticsearch health is green"
      return 0
    fi
    sleep "${POLL_INTERVAL_SECONDS}"
  done
  fail "Elasticsearch did not reach health=green (last phase=${phase:-<empty>}, health=${health:-<empty>})"
}

wait_for_kibana_health() {
  local deadline=$((SECONDS + HEALTH_TIMEOUT_SECONDS))
  local health=""
  local previous_health=""

  log "Waiting up to ${HEALTH_TIMEOUT_SECONDS}s for Kibana health=green"
  while (( SECONDS < deadline )); do
    health="$(kubectl get kibana "${STACK_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.health}' 2>/dev/null || true)"
    if [[ "${health:-<empty>}" != "${previous_health}" ]]; then
      log "Kibana health=${health:-<empty>}"
      previous_health="${health:-<empty>}"
    fi
    if [[ "${health}" == "green" ]]; then
      log "Kibana health is green"
      return 0
    fi
    sleep "${POLL_INTERVAL_SECONDS}"
  done
  fail "Kibana did not reach health=green (last health=${health:-<empty>})"
}

wait_for_matching_pods() {
  local component="$1"
  local selector="$2"
  local deadline=$((SECONDS + POD_DISCOVERY_TIMEOUT_SECONDS))
  local pod_count=0

  log "Waiting for ${component} pods matching selector: ${selector}"
  while (( SECONDS < deadline )); do
    pod_count="$(kubectl get pods -n "${NAMESPACE}" -l "${selector}" -o name 2>/dev/null | awk 'NF {count++} END {print count+0}')"
    if (( pod_count > 0 )); then
      log "Found ${pod_count} ${component} pod(s); waiting for Ready condition"
      kubectl wait --for=condition=Ready pod \
        -l "${selector}" \
        -n "${NAMESPACE}" \
        --timeout="${POD_READY_TIMEOUT_SECONDS}s"
      return 0
    fi
    sleep "${POLL_INTERVAL_SECONDS}"
  done
  fail "No ${component} pods appeared for selector '${selector}' within ${POD_DISCOVERY_TIMEOUT_SECONDS}s"
}

discover_kibana_selector() {
  local deadline=$((SECONDS + POD_DISCOVERY_TIMEOUT_SECONDS))
  local label_value=""

  log "Discovering the ECK Kibana selector from created pod labels"
  while (( SECONDS < deadline )); do
    while IFS= read -r label_value; do
      if [[ "${label_value}" == "${STACK_NAME}" ]]; then
        KIBANA_SELECTOR="kibana.k8s.elastic.co/name=${label_value}"
        log "Detected Kibana selector: ${KIBANA_SELECTOR}"
        return 0
      fi
    done < <(
      kubectl get pods -n "${NAMESPACE}" \
        -l common.k8s.elastic.co/type=kibana \
        -o jsonpath='{range .items[*]}{.metadata.labels.kibana\.k8s\.elastic\.co/name}{"\n"}{end}' \
        2>/dev/null || true
    )
    sleep "${POLL_INTERVAL_SECONDS}"
  done
  fail "Could not detect the Kibana ECK selector from pod labels"
}

for command in kubectl helm curl openssl; do
  command -v "$command" >/dev/null 2>&1 || fail "Missing command: ${command}"
done

available_kib="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
if ! kubectl -n "${NAMESPACE}" get elasticsearch "${STACK_NAME}" >/dev/null 2>&1 && (( available_kib < 4 * 1024 * 1024 )); then
  fail "Available RAM is below 4 GiB. Inspect existing workloads before deployment."
fi

log "Installing ECK operator ${ECK_VERSION}"
DIAGNOSTICS_ENABLED=true
helm repo add elastic https://helm.elastic.co --force-update >/dev/null
helm repo update elastic >/dev/null
helm upgrade --install elastic-operator elastic/eck-operator \
  --version "${ECK_VERSION}" \
  --namespace "${OPERATOR_NAMESPACE}" \
  --create-namespace \
  --wait --timeout 10m

kubectl rollout status statefulset/elastic-operator -n "${OPERATOR_NAMESPACE}" --timeout=5m

log "Installing Elasticsearch and Kibana with exporter temporarily disabled"
helm upgrade --install "${STACK_NAME}" "${ROOT_DIR}/charts/elastic-stack" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --values "${VALUES_FILE}" \
  --set exporter.enabled=false \
  --wait --timeout 2m

wait_for_resource elasticsearch "${STACK_NAME}" "${CR_TIMEOUT_SECONDS}"
wait_for_resource kibana "${STACK_NAME}" "${CR_TIMEOUT_SECONDS}"

wait_for_elasticsearch_health
wait_for_kibana_health

wait_for_matching_pods Elasticsearch "elasticsearch.k8s.elastic.co/cluster-name=${STACK_NAME}"
discover_kibana_selector
wait_for_matching_pods Kibana "${KIBANA_SELECTOR}"

NAMESPACE="${NAMESPACE}" STACK_NAME="${STACK_NAME}" "${METRICS_CONFIGURE_SCRIPT}"

log "Enabling exporter"
helm upgrade --install "${STACK_NAME}" "${ROOT_DIR}/charts/elastic-stack" \
  --namespace "${NAMESPACE}" \
  --values "${VALUES_FILE}" \
  --wait --timeout 10m

kubectl rollout status "deployment/${STACK_NAME}-exporter" -n "${NAMESPACE}" --timeout=5m
log "Deployment complete"
kubectl get elasticsearch,kibana,pods,pvc,svc -n "${NAMESPACE}"

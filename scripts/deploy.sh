#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-elastic-stack}"
OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE:-elastic-system}"
STACK_NAME="${STACK_NAME:-elastic-stack}"
ECK_VERSION="${ECK_VERSION:-3.5.0}"
VALUES_FILE="${VALUES_FILE:-${ROOT_DIR}/helm-values/non-bitnami-values.yaml}"

log() { printf '[deploy] %s\n' "$*"; }
fail() { printf '[deploy] ERROR: %s\n' "$*" >&2; exit 1; }

for command in kubectl helm curl openssl; do
  command -v "$command" >/dev/null 2>&1 || fail "Missing command: ${command}"
done

available_kib="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
if ! kubectl -n "${NAMESPACE}" get elasticsearch "${STACK_NAME}" >/dev/null 2>&1 && (( available_kib < 4 * 1024 * 1024 )); then
  fail "Available RAM is below 4 GiB. Inspect existing workloads before deployment."
fi

log "Installing ECK operator ${ECK_VERSION}"
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

log "Waiting for Elasticsearch and Kibana readiness"
kubectl wait --for=condition=Ready pod \
  -l "elasticsearch.k8s.elastic.co/cluster-name=${STACK_NAME}" \
  -n "${NAMESPACE}" --timeout=15m
kubectl wait --for=condition=Ready pod \
  -l "kibana.k8s.elastic.co/name=${STACK_NAME}" \
  -n "${NAMESPACE}" --timeout=15m

NAMESPACE="${NAMESPACE}" STACK_NAME="${STACK_NAME}" "${ROOT_DIR}/scripts/configure-metrics-user.sh"

log "Enabling exporter"
helm upgrade --install "${STACK_NAME}" "${ROOT_DIR}/charts/elastic-stack" \
  --namespace "${NAMESPACE}" \
  --values "${VALUES_FILE}" \
  --wait --timeout 10m

kubectl rollout status "deployment/${STACK_NAME}-exporter" -n "${NAMESPACE}" --timeout=5m
log "Deployment complete"
kubectl get elasticsearch,kibana,pods,pvc,svc -n "${NAMESPACE}"

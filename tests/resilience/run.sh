#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAMESPACE="${NAMESPACE:-elastic-stack}"
STACK_NAME="${STACK_NAME:-elastic-stack}"

echo '[resilience] Re-running the idempotent deployment'
"${ROOT_DIR}/scripts/deploy.sh"
"${ROOT_DIR}/scripts/verify.sh"

pod="$(kubectl -n "${NAMESPACE}" get pod -l "elasticsearch.k8s.elastic.co/cluster-name=${STACK_NAME}" -o jsonpath='{.items[0].metadata.name}')"
[[ -n "${pod}" ]] || { echo 'Elasticsearch pod not found' >&2; exit 1; }

echo "[resilience] Recreating Elasticsearch pod ${pod}"
kubectl -n "${NAMESPACE}" delete pod "${pod}" --wait=true
kubectl wait --for=condition=Ready pod \
  -l "elasticsearch.k8s.elastic.co/cluster-name=${STACK_NAME}" \
  -n "${NAMESPACE}" --timeout=15m

echo '[resilience] Verifying the persisted document after pod recreation'
"${ROOT_DIR}/scripts/verify.sh"
echo '[resilience] Persistence and idempotency checks passed'

#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RENDERED="$(mktemp)"
SECURITY_RENDERED="$(mktemp)"
trap 'rm -f "${RENDERED}" "${SECURITY_RENDERED}"' EXIT

helm lint "${ROOT_DIR}/charts/elastic-stack" -f "${ROOT_DIR}/helm-values/non-bitnami-values.yaml"
helm template elastic-stack "${ROOT_DIR}/charts/elastic-stack" \
  --namespace elastic-stack \
  -f "${ROOT_DIR}/helm-values/non-bitnami-values.yaml" > "${RENDERED}"

if grep -Eqi 'docker\.io/bitnami|/opt/bitnami|/bitnami/' "${RENDERED}"; then
  echo 'Active render contains a forbidden Bitnami runtime dependency' >&2
  exit 1
fi

grep -q 'kind: Elasticsearch' "${RENDERED}"
grep -q 'kind: Kibana' "${RENDERED}"
grep -q 'ghcr.io/prometheus-community/elasticsearch-exporter:v1.11.0' "${RENDERED}"
grep -q 'runAsUser: 65534' "${RENDERED}"
grep -q 'runAsGroup: 65534' "${RENDERED}"
grep -q 'path: /healthz' "${RENDERED}"

helm template elastic-stack "${ROOT_DIR}/charts/elastic-stack" \
  --namespace elastic-stack \
  -f "${ROOT_DIR}/helm-values/non-bitnami-values.yaml" \
  --set exporter.containerSecurityContext.runAsUser=12345 \
  --set exporter.containerSecurityContext.runAsGroup=12345 > "${SECURITY_RENDERED}"
grep -q 'runAsUser: 12345' "${SECURITY_RENDERED}"
grep -q 'runAsGroup: 12345' "${SECURITY_RENDERED}"

"${ROOT_DIR}/tests/static/deploy-readiness-test.sh"
"${ROOT_DIR}/tests/static/metrics-tls-test.sh"
"${ROOT_DIR}/tests/static/collect-evidence-test.sh"
"${ROOT_DIR}/tests/static/verify-metrics-test.sh"

if command -v kubeconform >/dev/null 2>&1; then
  kubeconform -strict -summary -ignore-missing-schemas "${RENDERED}"
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  docker run --rm \
    -v "${RENDERED}:/rendered.yaml:ro" \
    ghcr.io/yannh/kubeconform:v0.7.0 \
    -strict -summary -ignore-missing-schemas /rendered.yaml
else
  echo 'kubeconform not installed; schema validation skipped'
fi

echo 'Static tests passed'

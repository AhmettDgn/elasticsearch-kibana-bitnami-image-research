#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RENDERED="$(mktemp)"
trap 'rm -f "${RENDERED}"' EXIT

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

"${ROOT_DIR}/tests/static/deploy-readiness-test.sh"

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

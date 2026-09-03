#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d)"
MOCK_BIN="${TEST_DIR}/bin"
OUTPUT_DIR="${TEST_DIR}/evidence"
SUCCESS_OUTPUT_DIR="${TEST_DIR}/evidence-success"
mkdir -p "${MOCK_BIN}"
trap 'rm -rf "${TEST_DIR}"' EXIT

cat > "${MOCK_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -u
args="$*"
if [[ "${args}" == *"get secret elastic-stack-es-elastic-user"* ]]; then
  printf 'mock-elastic-password'
elif [[ "${args}" == *"get secret elastic-stack-es-http-certs-public"* ]] || \
     [[ "${args}" == *"get secret elastic-stack-kb-http-certs-public"* ]]; then
  printf 'ZHVtbXktY2E='
elif [[ "${args}" == *"port-forward"* ]]; then
  printf 'mock port-forward ready\n' >&2
  sleep 30
else
  printf 'mock kubectl evidence for %s\n' "${args}"
fi
EOF

cat > "${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -u
all_args="$*"
output_file=""
url=""
while (( $# > 0 )); do
  case "$1" in
    --output)
      output_file="$2"
      shift 2
      ;;
    --write-out)
      shift 2
      ;;
    http://*|https://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "${url}" == https://elastic-stack-es-http.elastic-stack.svc:* ]]; then
  [[ "${all_args}" == *"--cacert "* ]] || { printf 'missing Elasticsearch CA verification\n' >&2; exit 60; }
  [[ "${all_args}" == *"--resolve elastic-stack-es-http.elastic-stack.svc:19200:127.0.0.1"* ]] || { printf 'missing Elasticsearch SAN resolve\n' >&2; exit 60; }
fi
if [[ "${url}" == https://elastic-stack-kb-http.elastic-stack.svc:* ]]; then
  [[ "${all_args}" == *"--cacert "* ]] || { printf 'missing Kibana CA verification\n' >&2; exit 60; }
  [[ "${all_args}" == *"--resolve elastic-stack-kb-http.elastic-stack.svc:15601:127.0.0.1"* ]] || { printf 'missing Kibana SAN resolve\n' >&2; exit 60; }
fi
[[ "${all_args}" != *"--insecure"* ]] || { printf 'TLS verification bypassed\n' >&2; exit 60; }

case "${url}" in
  */demo-index)
    [[ "${all_args}" == *"--head"* ]] || { printf 'index preflight must use HEAD\n' >&2; exit 2; }
    if [[ "${MOCK_INDEX_EXISTS:-false}" == "true" ]]; then
      printf '200'
    else
      printf '404'
    fi
    ;;
  */_cluster/health\?pretty)
    printf '{"status":"green"}\n' > "${output_file}"
    printf '200'
    ;;
  */demo-index/_search\?pretty\&q=_id:1)
    if [[ "${MOCK_INDEX_EXISTS:-false}" != "true" ]]; then
      printf 'search endpoint must not be called when the index preflight returns 404\n' >&2
      exit 99
    fi
    printf '{"hits":{"total":{"value":1},"hits":[{"_id":"1"}]}}\n' > "${output_file}"
    printf '200'
    ;;
  */api/status)
    printf '{"status":{"overall":{"level":"available"}}}\n' > "${output_file}"
    printf '200'
    ;;
  */metrics)
    printf '# HELP elasticsearch_up Whether Elasticsearch is reachable\nelasticsearch_up 1\n' > "${output_file}"
    printf '200'
    ;;
  *)
    printf '404'
    printf 'curl: (22) unexpected endpoint: %s\n' "${url}" >&2
    exit 22
    ;;
esac
EOF

chmod +x "${MOCK_BIN}/kubectl" "${MOCK_BIN}/curl"

set +e
script_output="$(
  PATH="${MOCK_BIN}:/usr/bin:/bin" \
  EVIDENCE_OUTPUT_DIR="${OUTPUT_DIR}" \
  EVIDENCE_DATE="test" \
  "${ROOT_DIR}/scripts/collect-evidence.sh" 2>&1
)"
script_exit=$?
set -e

[[ "${script_exit}" -ne 0 ]]
grep -q 'Evidence index demo-index does not exist' <<<"${script_output}"
grep -q 'Partial evidence written' <<<"${script_output}"

grep -q '"status":"green"' "${OUTPUT_DIR}/cluster-health.json"
grep -q '"level":"available"' "${OUTPUT_DIR}/kibana-status.json"
grep -q '^elasticsearch_up 1' "${OUTPUT_DIR}/exporter-metrics.txt"
grep -q 'HTTP status: 404' "${OUTPUT_DIR}/search-result.json.error.txt"
grep -q 'Elasticsearch cluster health endpoint: success' "${OUTPUT_DIR}/report.md"
grep -q 'Elasticsearch document search endpoint: skipped — /demo-index/_search (index does not exist)' "${OUTPUT_DIR}/report.md"
grep -q 'Kibana status endpoint: success' "${OUTPUT_DIR}/report.md"
grep -q 'Exporter metrics endpoint: success' "${OUTPUT_DIR}/report.md"

if grep -R -q 'mock-elastic-password' "${OUTPUT_DIR}"; then
  echo 'Credential content leaked into evidence files' >&2
  exit 1
fi

success_output="$(
  PATH="${MOCK_BIN}:/usr/bin:/bin" \
  MOCK_INDEX_EXISTS=true \
  EVIDENCE_OUTPUT_DIR="${SUCCESS_OUTPUT_DIR}" \
  EVIDENCE_DATE="test-success" \
  "${ROOT_DIR}/scripts/collect-evidence.sh" 2>&1
)"

grep -q 'Wrote sanitized evidence' <<<"${success_output}"
grep -q '"value":1' "${SUCCESS_OUTPUT_DIR}/search-result.json"
grep -q 'Elasticsearch document search endpoint: success — /demo-index/_search (HTTP 200)' "${SUCCESS_OUTPUT_DIR}/report.md"

echo 'Collect-evidence partial-output regression test passed'

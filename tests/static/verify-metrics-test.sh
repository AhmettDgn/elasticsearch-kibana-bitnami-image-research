#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d)"
MOCK_BIN="${TEST_DIR}/bin"
MOCK_STATE_DIR="${TEST_DIR}/state"
mkdir -p "${MOCK_BIN}" "${MOCK_STATE_DIR}"
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
  sleep 30
fi
EOF

cat > "${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -u
output_file=""
url=""
while (( $# > 0 )); do
  case "$1" in
    --output)
      output_file="$2"
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

case "${url}" in
  https://elastic-stack-es-http.elastic-stack.svc:19200/)
    count_file="${MOCK_STATE_DIR}/es-probe-count"
    count="$(cat "${count_file}" 2>/dev/null || printf '0')"
    count=$((count + 1))
    printf '%s' "${count}" > "${count_file}"
    if (( count == 1 )); then
      printf 'curl: (7) Failed to connect during mock bootstrap\n' >&2
      exit 7
    fi
    ;;
  https://elastic-stack-es-http.elastic-stack.svc:19200/demo-index)
    printf '200'
    ;;
  */demo-index/_doc/1\?refresh=wait_for)
    ;;
  */demo-index/_search\?q=_id:1)
    printf '{"hits":[{"_source":{"message":"hello from the Bitnami-free ECK deployment"}}]}'
    ;;
  */_cluster/health)
    printf '{"status":"green"}'
    ;;
  */api/status)
    printf '{"status":{"overall":{"level":"available"}}}'
    ;;
  http://127.0.0.1:19114/healthz)
    ;;
  http://127.0.0.1:19114/metrics)
    if [[ -z "${output_file}" ]]; then
      printf 'curl: (23) Failure writing output to destination\n' >&2
      exit 23
    fi
    printf '# HELP elasticsearch_up Whether Elasticsearch is reachable\nelasticsearch_up 1\nelasticsearch_cluster_health_number_of_data_nodes 1\n' > "${output_file}"
    ;;
  *)
    printf 'unexpected mock URL: %s\n' "${url}" >&2
    exit 22
    ;;
esac
EOF

chmod +x "${MOCK_BIN}/kubectl" "${MOCK_BIN}/curl"
export MOCK_STATE_DIR

verify_output="$(
  PATH="${MOCK_BIN}:/usr/bin:/bin" \
  ES_API_RETRY_ATTEMPTS=3 \
  ES_API_RETRY_INTERVAL_SECONDS=0 \
  "${ROOT_DIR}/scripts/verify.sh" 2>&1
)"

grep -q 'Elasticsearch API is not reachable yet (attempt 1/3); retrying' <<<"${verify_output}"
grep -q 'All integration checks passed' <<<"${verify_output}"
if grep -q 'curl: (7)' <<<"${verify_output}"; then
  echo 'Transient Elasticsearch probe error was printed as a curl error' >&2
  exit 1
fi
if grep -q 'curl: (23)' <<<"${verify_output}"; then
  echo 'Exporter metrics check still produced a pipeline/SIGPIPE false-negative' >&2
  exit 1
fi

echo 'Verify metrics regression test passed'

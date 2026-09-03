#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d)"
MOCK_BIN="${TEST_DIR}/bin"
MOCK_STATE_DIR="${TEST_DIR}/state"
mkdir -p "${MOCK_BIN}" "${MOCK_STATE_DIR}"
trap 'rm -rf "${TEST_DIR}"' EXIT

cat > "${TEST_DIR}/deploy.sh" <<'EOF'
#!/usr/bin/env bash
printf 'mock deploy complete\n'
EOF

cat > "${TEST_DIR}/verify.sh" <<'EOF'
#!/usr/bin/env bash
printf 'mock integration verification complete\n'
EOF

cat > "${MOCK_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'kubectl %s\n' "$*" >> "${MOCK_STATE_DIR}/kubectl-calls.log"
args="$*"

if [[ "${args}" == *"get secret elastic-stack-es-elastic-user"* ]]; then
  printf 'mock-elastic-password'
  exit 0
fi
if [[ "${args}" == *"get secret elastic-stack-es-http-certs-public"* ]]; then
  printf 'ZHVtbXktY2E='
  exit 0
fi
if [[ "${args}" == *"port-forward service/elastic-stack-es-http"* ]]; then
  sleep 30
  exit 0
fi
if [[ "${args}" == *"delete pod elastic-stack-es-default-0"* ]]; then
  : > "${MOCK_STATE_DIR}/deleted"
  exit 0
fi
if [[ "${args}" == *"get pods"*"metadata.uid"* ]]; then
  if [[ ! -f "${MOCK_STATE_DIR}/deleted" ]]; then
    printf 'elastic-stack-es-default-0|old-uid'
    exit 0
  fi
  if [[ "${MOCK_NO_RECREATED_POD:-false}" == "true" ]]; then
    exit 0
  fi
  count_file="${MOCK_STATE_DIR}/pod-poll-count"
  count="$(cat "${count_file}" 2>/dev/null || printf '0')"
  count=$((count + 1))
  printf '%s' "${count}" > "${count_file}"
  if (( count >= 3 )); then
    printf 'elastic-stack-es-default-0|new-uid'
  fi
  exit 0
fi
if [[ "${args}" == *"wait --for=condition=Ready pod/elastic-stack-es-default-0"* ]]; then
  exit 0
fi
if [[ "${args}" == *"get elasticsearch elastic-stack"*"{.status.phase}"* ]]; then
  printf 'Ready'
  exit 0
fi
if [[ "${args}" == *"get elasticsearch elastic-stack"*"{.status.health}"* ]]; then
  printf 'green'
  exit 0
fi
printf 'mock diagnostic output\n'
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
  https://elastic-stack-es-http.elastic-stack.svc:19201/)
    exit 0
    ;;
  https://elastic-stack-es-http.elastic-stack.svc:19201/demo-index/_doc/1)
    printf '{"_index":"demo-index","_id":"1","found":true}\n' > "${output_file}"
    exit 0
    ;;
  *)
    printf 'unexpected URL: %s\n' "${url}" >&2
    exit 22
    ;;
esac
EOF

chmod +x "${TEST_DIR}/deploy.sh" "${TEST_DIR}/verify.sh" "${MOCK_BIN}/kubectl" "${MOCK_BIN}/curl"
export MOCK_STATE_DIR

success_output="$(
  PATH="${MOCK_BIN}:/usr/bin:/bin" \
  DEPLOY_SCRIPT="${TEST_DIR}/deploy.sh" \
  VERIFY_SCRIPT="${TEST_DIR}/verify.sh" \
  POD_DISCOVERY_ATTEMPTS=5 \
  POD_DISCOVERY_INTERVAL_SECONDS=0 \
  CR_HEALTH_ATTEMPTS=2 \
  CR_HEALTH_INTERVAL_SECONDS=0 \
  API_RETRY_ATTEMPTS=2 \
  API_RETRY_INTERVAL_SECONDS=0 \
  "${ROOT_DIR}/tests/resilience/run.sh" 2>&1
)"

grep -q 'Document demo-index/_doc/1 found=true (before-recreation)' <<<"${success_output}"
grep -q 'Waiting for recreated Elasticsearch pod (1/5)' <<<"${success_output}"
grep -q 'Recreated Elasticsearch pod elastic-stack-es-default-0 appeared; waiting for Ready' <<<"${success_output}"
grep -q 'Elasticsearch phase=Ready health=green after pod recreation' <<<"${success_output}"
grep -q 'Document demo-index/_doc/1 found=true (after-recreation)' <<<"${success_output}"
grep -q 'Persistence and idempotency checks passed' <<<"${success_output}"
grep -q 'wait --for=condition=Ready pod/elastic-stack-es-default-0' "${MOCK_STATE_DIR}/kubectl-calls.log"
if grep -q 'wait --for=condition=Ready pod -l' "${MOCK_STATE_DIR}/kubectl-calls.log"; then
  echo 'Resilience test used selector wait before a concrete pod was discovered' >&2
  exit 1
fi

rm -f "${MOCK_STATE_DIR}/deleted" "${MOCK_STATE_DIR}/pod-poll-count"
: > "${MOCK_STATE_DIR}/kubectl-calls.log"
set +e
timeout_output="$(
  PATH="${MOCK_BIN}:/usr/bin:/bin" \
  MOCK_NO_RECREATED_POD=true \
  DEPLOY_SCRIPT="${TEST_DIR}/deploy.sh" \
  VERIFY_SCRIPT="${TEST_DIR}/verify.sh" \
  POD_DISCOVERY_ATTEMPTS=2 \
  POD_DISCOVERY_INTERVAL_SECONDS=0 \
  API_RETRY_ATTEMPTS=1 \
  API_RETRY_INTERVAL_SECONDS=0 \
  "${ROOT_DIR}/tests/resilience/run.sh" 2>&1
)"
timeout_exit=$?
set -e

[[ "${timeout_exit}" -ne 0 ]]
grep -q 'Recreated Elasticsearch pod did not appear' <<<"${timeout_output}"
grep -q 'automatic diagnostics' <<<"${timeout_output}"
grep -q 'get elasticsearch,pods,pvc -n elastic-stack' "${MOCK_STATE_DIR}/kubectl-calls.log"
grep -q 'get events -n elastic-stack --sort-by=.lastTimestamp' "${MOCK_STATE_DIR}/kubectl-calls.log"
grep -q 'describe elasticsearch elastic-stack -n elastic-stack' "${MOCK_STATE_DIR}/kubectl-calls.log"

echo 'Resilience recreation regression tests passed'

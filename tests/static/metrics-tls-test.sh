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
  printf 'mock port-forward is running\n' >&2
  sleep 30
  exit 0
fi
if [[ "${args}" == *"get secret elasticsearch-exporter-credentials"* ]]; then
  exit 1
fi
if [[ "${args}" == *"create secret generic"* ]]; then
  printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: mock\n'
  exit 0
fi
if [[ "${args}" == *"apply -f -"* ]]; then
  cat >/dev/null
  exit 0
fi
exit 0
EOF

cat > "${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'curl %s\n' "$*" >> "${MOCK_STATE_DIR}/curl-calls.log"
if [[ "${MOCK_CURL_MODE:-retry}" == "fail" ]]; then
  printf 'curl: (60) mock TLS failure\n' >&2
  exit 60
fi
if [[ "$*" == *"/_security/"* ]]; then
  exit 0
fi
count_file="${MOCK_STATE_DIR}/curl-count"
count="$(cat "${count_file}" 2>/dev/null || printf '0')"
count=$((count + 1))
printf '%s' "${count}" > "${count_file}"
if (( count == 1 )); then
  printf 'curl: (7) mock connection startup delay\n' >&2
  exit 7
fi
exit 0
EOF

cat > "${MOCK_BIN}/openssl" <<'EOF'
#!/usr/bin/env bash
printf '0123456789abcdef0123456789abcdef01234567\n'
EOF

cat > "${MOCK_BIN}/ss" <<'EOF'
#!/usr/bin/env bash
if [[ "${MOCK_PORT_IN_USE:-false}" == "true" ]]; then
  printf 'LISTEN 0 4096 127.0.0.1:19445 0.0.0.0:*\n'
fi
EOF

chmod +x "${MOCK_BIN}/kubectl" "${MOCK_BIN}/curl" "${MOCK_BIN}/openssl" "${MOCK_BIN}/ss"
export MOCK_STATE_DIR

success_output="$(
  PATH="${MOCK_BIN}:/usr/bin:/bin" \
  LOCAL_PORT=19443 \
  API_RETRY_ATTEMPTS=3 \
  RETRY_INTERVAL_SECONDS=0 \
  "${ROOT_DIR}/scripts/configure-metrics-user.sh" 2>&1
)"

grep -q 'Elasticsearch API probe 1/3 failed' <<<"${success_output}"
grep -q -- '--resolve elastic-stack-es-http.elastic-stack.svc:19443:127.0.0.1' "${MOCK_STATE_DIR}/curl-calls.log"
grep -q -- '--noproxy elastic-stack-es-http.elastic-stack.svc' "${MOCK_STATE_DIR}/curl-calls.log"
grep -q 'https://elastic-stack-es-http.elastic-stack.svc:19443/' "${MOCK_STATE_DIR}/curl-calls.log"
if grep -Eq -- '--insecure|(^| )-k( |$)|https://127\.0\.0\.1' "${MOCK_STATE_DIR}/curl-calls.log"; then
  echo 'TLS verification was bypassed or the loopback IP was used as HTTPS hostname' >&2
  exit 1
fi
grep -q 'get secret elastic-stack-es-http-certs-public' "${MOCK_STATE_DIR}/kubectl-calls.log"

: > "${MOCK_STATE_DIR}/curl-calls.log"
: > "${MOCK_STATE_DIR}/kubectl-calls.log"
set +e
timeout_output="$(
  PATH="${MOCK_BIN}:/usr/bin:/bin" \
  MOCK_CURL_MODE=fail \
  LOCAL_PORT=19444 \
  API_RETRY_ATTEMPTS=2 \
  RETRY_INTERVAL_SECONDS=0 \
  "${ROOT_DIR}/scripts/configure-metrics-user.sh" 2>&1
)"
timeout_exit=$?
set -e

[[ "${timeout_exit}" -ne 0 ]]
grep -q '\[port-forward\] mock port-forward is running' <<<"${timeout_output}"
grep -q '\[curl\] curl: (60) mock TLS failure' <<<"${timeout_output}"

: > "${MOCK_STATE_DIR}/kubectl-calls.log"
set +e
port_in_use_output="$(
  PATH="${MOCK_BIN}:/usr/bin:/bin" \
  MOCK_PORT_IN_USE=true \
  LOCAL_PORT=19445 \
  "${ROOT_DIR}/scripts/configure-metrics-user.sh" 2>&1
)"
port_in_use_exit=$?
set -e

[[ "${port_in_use_exit}" -ne 0 ]]
grep -q 'LOCAL_PORT 19445 is already in use' <<<"${port_in_use_output}"
if grep -q 'port-forward' "${MOCK_STATE_DIR}/kubectl-calls.log"; then
  echo 'Port-forward was started despite the occupied local port' >&2
  exit 1
fi

echo 'Metrics TLS/SAN regression tests passed'

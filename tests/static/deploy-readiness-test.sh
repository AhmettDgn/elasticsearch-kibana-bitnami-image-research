#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d)"
MOCK_BIN="${TEST_DIR}/bin"
MOCK_STATE_DIR="${TEST_DIR}/state"
mkdir -p "${MOCK_BIN}" "${MOCK_STATE_DIR}"
trap 'rm -rf "${TEST_DIR}"' EXIT

cat > "${MOCK_BIN}/helm" <<'EOF'
#!/usr/bin/env bash
printf 'helm %s\n' "$*" >> "${MOCK_STATE_DIR}/calls.log"
exit 0
EOF

cat > "${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "${MOCK_BIN}/openssl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "${TEST_DIR}/configure-metrics-user.sh" <<'EOF'
#!/usr/bin/env bash
printf 'metrics-configured\n' >> "${MOCK_STATE_DIR}/calls.log"
exit 0
EOF

cat > "${MOCK_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'kubectl %s\n' "$*" >> "${MOCK_STATE_DIR}/calls.log"
args="$*"

if [[ "${args}" == *"get elasticsearch elastic-stack -n elastic-stack"* && "${args}" != *"jsonpath"* ]]; then
  count_file="${MOCK_STATE_DIR}/es-resource-count"
  count="$(cat "${count_file}" 2>/dev/null || printf '0')"
  count=$((count + 1))
  printf '%s' "${count}" > "${count_file}"
  (( count >= 2 ))
  exit $?
fi

if [[ "${args}" == *"get kibana elastic-stack -n elastic-stack"* && "${args}" != *"jsonpath"* ]]; then
  count_file="${MOCK_STATE_DIR}/kb-resource-count"
  count="$(cat "${count_file}" 2>/dev/null || printf '0')"
  count=$((count + 1))
  printf '%s' "${count}" > "${count_file}"
  (( count >= 2 ))
  exit $?
fi

if [[ "${args}" == *"get elasticsearch elastic-stack"*"{.status.phase}"* ]]; then
  printf 'ApplyingChanges'
  exit 0
fi

if [[ "${args}" == *"get elasticsearch elastic-stack"*"{.status.health}"* ]]; then
  if [[ "${MOCK_MODE:-success}" == "timeout" ]]; then
    printf 'unknown'
    exit 0
  fi
  count_file="${MOCK_STATE_DIR}/es-health-count"
  count="$(cat "${count_file}" 2>/dev/null || printf '0')"
  count=$((count + 1))
  printf '%s' "${count}" > "${count_file}"
  if (( count < 2 )); then printf 'unknown'; else printf 'green'; fi
  exit 0
fi

if [[ "${args}" == *"get kibana elastic-stack"*"{.status.health}"* ]]; then
  count_file="${MOCK_STATE_DIR}/kb-health-count"
  count="$(cat "${count_file}" 2>/dev/null || printf '0')"
  count=$((count + 1))
  printf '%s' "${count}" > "${count_file}"
  if (( count < 2 )); then printf 'red'; else printf 'green'; fi
  exit 0
fi

if [[ "${args}" == *"common.k8s.elastic.co/type=kibana"* ]]; then
  printf 'elastic-stack\n'
  exit 0
fi

if [[ "${args}" == *"get pods"*"elasticsearch.k8s.elastic.co/cluster-name=elastic-stack"*"-o name"* ]]; then
  count_file="${MOCK_STATE_DIR}/es-pod-count"
  count="$(cat "${count_file}" 2>/dev/null || printf '0')"
  count=$((count + 1))
  printf '%s' "${count}" > "${count_file}"
  (( count >= 2 )) || exit 0
  printf 'pod/elastic-stack-es-default-0\n'
  exit 0
fi

if [[ "${args}" == *"get pods"*"kibana.k8s.elastic.co/name=elastic-stack"*"-o name"* ]]; then
  count_file="${MOCK_STATE_DIR}/kb-pod-count"
  count="$(cat "${count_file}" 2>/dev/null || printf '0')"
  count=$((count + 1))
  printf '%s' "${count}" > "${count_file}"
  (( count >= 2 )) || exit 0
  printf 'pod/elastic-stack-kb-mock\n'
  exit 0
fi

exit 0
EOF

chmod +x "${MOCK_BIN}/helm" "${MOCK_BIN}/kubectl" "${MOCK_BIN}/curl" "${MOCK_BIN}/openssl" "${TEST_DIR}/configure-metrics-user.sh"
export MOCK_STATE_DIR

success_output="$(
  PATH="${MOCK_BIN}:/usr/bin:/bin" \
  METRICS_CONFIGURE_SCRIPT="${TEST_DIR}/configure-metrics-user.sh" \
  CR_TIMEOUT_SECONDS=2 \
  HEALTH_TIMEOUT_SECONDS=2 \
  POD_DISCOVERY_TIMEOUT_SECONDS=2 \
  POD_READY_TIMEOUT_SECONDS=2 \
  POLL_INTERVAL_SECONDS=0 \
  "${ROOT_DIR}/scripts/deploy.sh" 2>&1
)"

grep -q 'Elasticsearch phase=ApplyingChanges health=unknown' <<<"${success_output}"
grep -q 'Elasticsearch health is green' <<<"${success_output}"
grep -q 'Kibana health=red' <<<"${success_output}"
grep -q 'Kibana health is green' <<<"${success_output}"
grep -q 'Detected Kibana selector: kibana.k8s.elastic.co/name=elastic-stack' <<<"${success_output}"
grep -q 'metrics-configured' "${MOCK_STATE_DIR}/calls.log"
[[ "$(cat "${MOCK_STATE_DIR}/es-resource-count")" -ge 2 ]]
[[ "$(cat "${MOCK_STATE_DIR}/kb-resource-count")" -ge 2 ]]
[[ "$(cat "${MOCK_STATE_DIR}/es-pod-count")" -ge 2 ]]
[[ "$(cat "${MOCK_STATE_DIR}/kb-pod-count")" -ge 2 ]]

: > "${MOCK_STATE_DIR}/calls.log"
set +e
timeout_output="$(
  PATH="${MOCK_BIN}:/usr/bin:/bin" \
  MOCK_MODE=timeout \
  METRICS_CONFIGURE_SCRIPT="${TEST_DIR}/configure-metrics-user.sh" \
  CR_TIMEOUT_SECONDS=2 \
  HEALTH_TIMEOUT_SECONDS=1 \
  POD_DISCOVERY_TIMEOUT_SECONDS=2 \
  POD_READY_TIMEOUT_SECONDS=2 \
  POLL_INTERVAL_SECONDS=1 \
  "${ROOT_DIR}/scripts/deploy.sh" 2>&1
)"
timeout_exit=$?
set -e

[[ "${timeout_exit}" -ne 0 ]]
grep -q 'automatic diagnostics' <<<"${timeout_output}"
grep -q 'kubectl describe pods -n elastic-stack' "${MOCK_STATE_DIR}/calls.log"
grep -q 'kubectl get events -n elastic-stack --sort-by=.lastTimestamp' "${MOCK_STATE_DIR}/calls.log"
grep -q 'kubectl logs -n elastic-system statefulset/elastic-operator --tail=150' "${MOCK_STATE_DIR}/calls.log"

echo 'Deploy readiness regression tests passed'

#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-elastic-stack}"
STACK_NAME="${STACK_NAME:-elastic-stack}"
INDEX_NAME="${INDEX_NAME:-demo-index}"
DATE_DIR="${EVIDENCE_DATE:-$(date +%F)}"
OUTPUT_DIR="${EVIDENCE_OUTPUT_DIR:-${ROOT_DIR}/artifacts/${DATE_DIR}}"
ES_PORT="${ES_PORT:-19200}"
KB_PORT="${KB_PORT:-15601}"
EXPORTER_PORT="${EXPORTER_PORT:-19114}"
ES_SERVICE_DNS="${ES_SERVICE_DNS:-${STACK_NAME}-es-http.${NAMESPACE}.svc}"
KB_SERVICE_DNS="${KB_SERVICE_DNS:-${STACK_NAME}-kb-http.${NAMESPACE}.svc}"

mkdir -p "${OUTPUT_DIR}"
tmp_dir="$(mktemp -d)"
pids=()
endpoint_results=()
failed_endpoints=0
cleanup() {
  for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

collect_endpoint() {
  local endpoint_name="$1"
  local endpoint_url="$2"
  local endpoint_path="$3"
  local output_file="$4"
  local filter_pattern="$5"
  shift 5

  local response_file
  local error_file
  local http_code
  local curl_exit
  response_file="$(mktemp "${tmp_dir}/response.XXXXXX")"
  error_file="$(mktemp "${tmp_dir}/curl-error.XXXXXX")"
  rm -f "${output_file}" "${output_file}.error.txt"

  set +e
  http_code="$(curl "$@" \
    --output "${response_file}" \
    --write-out '%{http_code}' \
    "${endpoint_url}" 2>"${error_file}")"
  curl_exit=$?
  set -e

  if (( curl_exit != 0 )); then
    printf '[evidence] ERROR: %s failed: %s (HTTP %s, curl exit %s)\n' \
      "${endpoint_name}" "${endpoint_url}" "${http_code:-unknown}" "${curl_exit}" >&2
    if [[ -s "${error_file}" ]]; then
      sed 's/^/[curl] /' "${error_file}" >&2
    fi
    printf 'Endpoint: %s\nPath: %s\nResult: failed\nHTTP status: %s\nCurl exit code: %s\n' \
      "${endpoint_name}" "${endpoint_path}" "${http_code:-unknown}" "${curl_exit}" > "${output_file}.error.txt"
    endpoint_results+=("- ${endpoint_name}: failed — ${endpoint_path} (HTTP ${http_code:-unknown}, curl exit ${curl_exit})")
    failed_endpoints=$((failed_endpoints + 1))
    return 0
  fi

  if [[ -n "${filter_pattern}" ]]; then
    if ! grep -E "${filter_pattern}" "${response_file}" > "${output_file}"; then
      rm -f "${output_file}"
      printf '[evidence] ERROR: %s returned HTTP %s but expected evidence was absent: %s\n' \
        "${endpoint_name}" "${http_code:-unknown}" "${endpoint_url}" >&2
      printf 'Endpoint: %s\nPath: %s\nResult: failed validation\nHTTP status: %s\n' \
        "${endpoint_name}" "${endpoint_path}" "${http_code:-unknown}" > "${output_file}.error.txt"
      endpoint_results+=("- ${endpoint_name}: failed validation — ${endpoint_path} (HTTP ${http_code:-unknown})")
      failed_endpoints=$((failed_endpoints + 1))
      return 0
    fi
  else
    mv "${response_file}" "${output_file}"
  fi

  endpoint_results+=("- ${endpoint_name}: success — ${endpoint_path} (HTTP ${http_code})")
}

kubectl get nodes -o wide > "${OUTPUT_DIR}/nodes.txt"
kubectl get pods -n "${NAMESPACE}" -o wide > "${OUTPUT_DIR}/pods.txt"
kubectl get pvc -n "${NAMESPACE}" > "${OUTPUT_DIR}/pvc.txt"
kubectl get services -n "${NAMESPACE}" > "${OUTPUT_DIR}/services.txt"

elastic_password="$(kubectl -n "${NAMESPACE}" get secret "${STACK_NAME}-es-elastic-user" -o go-template='{{.data.elastic | base64decode}}')"
kubectl -n "${NAMESPACE}" get secret "${STACK_NAME}-es-http-certs-public" -o jsonpath='{.data.tls\.crt}' | base64 -d > "${tmp_dir}/es-ca.crt"
kubectl -n "${NAMESPACE}" get secret "${STACK_NAME}-kb-http-certs-public" -o jsonpath='{.data.tls\.crt}' | base64 -d > "${tmp_dir}/kb-ca.crt"

kubectl -n "${NAMESPACE}" port-forward "service/${STACK_NAME}-es-http" "${ES_PORT}:9200" --address 127.0.0.1 >"${tmp_dir}/es-pf.log" 2>&1 & pids+=("$!")
kubectl -n "${NAMESPACE}" port-forward "service/${STACK_NAME}-kb-http" "${KB_PORT}:5601" --address 127.0.0.1 >"${tmp_dir}/kb-pf.log" 2>&1 & pids+=("$!")
kubectl -n "${NAMESPACE}" port-forward "service/${STACK_NAME}-exporter" "${EXPORTER_PORT}:9114" --address 127.0.0.1 >"${tmp_dir}/exporter-pf.log" 2>&1 & pids+=("$!")
sleep 3

es_base_url="https://${ES_SERVICE_DNS}:${ES_PORT}"
kb_base_url="https://${KB_SERVICE_DNS}:${KB_PORT}"
es_curl_args=(--silent --show-error --fail --cacert "${tmp_dir}/es-ca.crt" --resolve "${ES_SERVICE_DNS}:${ES_PORT}:127.0.0.1" --noproxy "${ES_SERVICE_DNS}" --user "elastic:${elastic_password}")
kb_curl_args=(--silent --show-error --fail --cacert "${tmp_dir}/kb-ca.crt" --resolve "${KB_SERVICE_DNS}:${KB_PORT}:127.0.0.1" --noproxy "${KB_SERVICE_DNS}" --user "elastic:${elastic_password}")

index_exists=false
index_check_error="${tmp_dir}/index-check-error.log"
rm -f "${OUTPUT_DIR}/search-result.json" "${OUTPUT_DIR}/search-result.json.error.txt"
set +e
index_status="$(curl --silent --show-error \
  --cacert "${tmp_dir}/es-ca.crt" \
  --resolve "${ES_SERVICE_DNS}:${ES_PORT}:127.0.0.1" \
  --noproxy "${ES_SERVICE_DNS}" \
  --user "elastic:${elastic_password}" \
  --head --output /dev/null --write-out '%{http_code}' \
  "${es_base_url}/${INDEX_NAME}" 2>"${index_check_error}")"
index_check_exit=$?
set -e

if (( index_check_exit != 0 )); then
  printf '[evidence] ERROR: Evidence index check failed: %s/%s (HTTP %s, curl exit %s)\n' \
    "${es_base_url}" "${INDEX_NAME}" "${index_status:-unknown}" "${index_check_exit}" >&2
  [[ ! -s "${index_check_error}" ]] || sed 's/^/[curl] /' "${index_check_error}" >&2
  printf 'Endpoint: Elasticsearch evidence index check\nPath: /%s\nResult: failed\nHTTP status: %s\nCurl exit code: %s\n' \
    "${INDEX_NAME}" "${index_status:-unknown}" "${index_check_exit}" > "${OUTPUT_DIR}/search-result.json.error.txt"
  endpoint_results+=("- Elasticsearch evidence index check: failed — /${INDEX_NAME} (HTTP ${index_status:-unknown}, curl exit ${index_check_exit})")
  failed_endpoints=$((failed_endpoints + 1))
elif [[ "${index_status}" == "200" ]]; then
  index_exists=true
elif [[ "${index_status}" == "404" ]]; then
  printf '[evidence] ERROR: Evidence index %s does not exist\n' "${INDEX_NAME}" >&2
  printf 'Endpoint: Elasticsearch evidence index check\nPath: /%s\nResult: index does not exist\nHTTP status: 404\n' \
    "${INDEX_NAME}" > "${OUTPUT_DIR}/search-result.json.error.txt"
  endpoint_results+=("- Elasticsearch document search endpoint: skipped — /${INDEX_NAME}/_search (index does not exist)")
  failed_endpoints=$((failed_endpoints + 1))
else
  printf '[evidence] ERROR: Evidence index check returned unexpected HTTP %s: %s/%s\n' \
    "${index_status:-unknown}" "${es_base_url}" "${INDEX_NAME}" >&2
  printf 'Endpoint: Elasticsearch evidence index check\nPath: /%s\nResult: unexpected response\nHTTP status: %s\n' \
    "${INDEX_NAME}" "${index_status:-unknown}" > "${OUTPUT_DIR}/search-result.json.error.txt"
  endpoint_results+=("- Elasticsearch evidence index check: failed — /${INDEX_NAME} (unexpected HTTP ${index_status:-unknown})")
  failed_endpoints=$((failed_endpoints + 1))
fi

collect_endpoint \
  "Elasticsearch cluster health endpoint" \
  "${es_base_url}/_cluster/health?pretty" \
  "/_cluster/health" \
  "${OUTPUT_DIR}/cluster-health.json" \
  "" \
  "${es_curl_args[@]}"

if [[ "${index_exists}" == "true" ]]; then
  collect_endpoint \
    "Elasticsearch document search endpoint" \
    "${es_base_url}/${INDEX_NAME}/_search?pretty&q=_id:1" \
    "/${INDEX_NAME}/_search" \
    "${OUTPUT_DIR}/search-result.json" \
    "" \
    "${es_curl_args[@]}"
fi

collect_endpoint \
  "Kibana status endpoint" \
  "${kb_base_url}/api/status" \
  "/api/status" \
  "${OUTPUT_DIR}/kibana-status.json" \
  "" \
  "${kb_curl_args[@]}"

collect_endpoint \
  "Exporter metrics endpoint" \
  "http://127.0.0.1:${EXPORTER_PORT}/metrics" \
  "/metrics" \
  "${OUTPUT_DIR}/exporter-metrics.txt" \
  '^(# (HELP|TYPE) elasticsearch_|elasticsearch_)' \
  --silent --show-error --fail
unset elastic_password es_curl_args kb_curl_args index_status

{
cat <<EOF
# Deployment Evidence - ${DATE_DIR}

- Namespace: \`${NAMESPACE}\`
- Stack resource: \`${STACK_NAME}\`
- Evidence was collected without passwords, tokens, authorization headers, Secret data, or SSH keys.
- Endpoint failures do not remove evidence already collected from other endpoints.

## Endpoint results

EOF
printf '%s\n' "${endpoint_results[@]}"
} > "${OUTPUT_DIR}/report.md"

if (( failed_endpoints > 0 )); then
  printf '[evidence] Partial evidence written to %s; %s endpoint check(s) failed. See report.md and *.error.txt.\n' \
    "${OUTPUT_DIR}" "${failed_endpoints}" >&2
  exit 1
fi

printf '[evidence] Wrote sanitized evidence to %s\n' "${OUTPUT_DIR}"

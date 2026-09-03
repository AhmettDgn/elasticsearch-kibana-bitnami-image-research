#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-elastic-stack}"
STACK_NAME="${STACK_NAME:-elastic-stack}"
INDEX_NAME="${INDEX_NAME:-bitnami-free-demo}"
DATE_DIR="${EVIDENCE_DATE:-$(date +%F)}"
OUTPUT_DIR="${ROOT_DIR}/artifacts/${DATE_DIR}"
ES_PORT="${ES_PORT:-19200}"
KB_PORT="${KB_PORT:-15601}"
EXPORTER_PORT="${EXPORTER_PORT:-19114}"
ES_SERVICE_DNS="${ES_SERVICE_DNS:-${STACK_NAME}-es-http.${NAMESPACE}.svc}"
KB_SERVICE_DNS="${KB_SERVICE_DNS:-${STACK_NAME}-kb-http.${NAMESPACE}.svc}"

mkdir -p "${OUTPUT_DIR}"
tmp_dir="$(mktemp -d)"
pids=()
cleanup() {
  for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

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

curl "${es_curl_args[@]}" "${es_base_url}/_cluster/health?pretty" > "${OUTPUT_DIR}/cluster-health.json"
curl "${es_curl_args[@]}" "${es_base_url}/${INDEX_NAME}/_search?pretty&q=_id:1" > "${OUTPUT_DIR}/search-result.json"
curl "${kb_curl_args[@]}" "${kb_base_url}/api/status" > "${OUTPUT_DIR}/kibana-status.json"
curl --silent --show-error --fail "http://127.0.0.1:${EXPORTER_PORT}/metrics" | grep -E '^(# (HELP|TYPE) elasticsearch_|elasticsearch_)' > "${OUTPUT_DIR}/exporter-metrics.txt"
unset elastic_password es_curl_args kb_curl_args

cat > "${OUTPUT_DIR}/report.md" <<EOF
# Deployment Evidence - ${DATE_DIR}

- Namespace: \`${NAMESPACE}\`
- Stack resource: \`${STACK_NAME}\`
- Evidence was collected without passwords, tokens, authorization headers, Secret data, or SSH keys.
- See the adjacent node, pod, PVC, service, health, search, Kibana, and exporter files.
EOF

printf '[evidence] Wrote sanitized evidence to %s\n' "${OUTPUT_DIR}"

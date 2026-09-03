#!/usr/bin/env bash
set -Eeuo pipefail

K3S_VERSION="${K3S_VERSION:-v1.36.3+k3s1}"
HELM_VERSION="${HELM_VERSION:-v3.18.6}"
REQUIRED_AVAILABLE_KIB=$((4 * 1024 * 1024))
REQUIRED_FREE_DISK_KIB=$((30 * 1024 * 1024))

log() { printf '[bootstrap] %s\n' "$*"; }
fail() { printf '[bootstrap] ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || fail "Run with sudo: sudo ./scripts/bootstrap-k3s.sh"
[[ "$(uname -s)" == "Linux" ]] || fail "This script supports Linux only"
[[ -r /etc/os-release ]] || fail "Cannot identify the operating system"
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || fail "Expected Ubuntu, found ${ID:-unknown}"
command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

case "$(uname -m)" in
  x86_64|amd64) helm_arch="amd64" ;;
  *) fail "Expected amd64/x86_64 architecture, found $(uname -m)" ;;
esac

available_kib="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
root_free_kib="$(df -Pk / | awk 'NR==2 {print $4}')"
swap_kib="$(awk '/SwapTotal:/ {print $2}' /proc/meminfo)"

if (( available_kib < REQUIRED_AVAILABLE_KIB )); then
  fail "At least 4 GiB available RAM is required. Review: ps aux --sort=-%mem | head -20"
fi
if (( root_free_kib < REQUIRED_FREE_DISK_KIB )); then
  fail "At least 30 GiB free disk is required on /"
fi
if (( swap_kib != 0 )); then
  fail "Swap must be disabled for this lab deployment"
fi

log "Persisting vm.max_map_count=262144"
printf 'vm.max_map_count=262144\n' > /etc/sysctl.d/99-elasticsearch.conf
sysctl --system >/dev/null
[[ "$(sysctl -n vm.max_map_count)" -ge 262144 ]] || fail "vm.max_map_count validation failed"

if command -v k3s >/dev/null 2>&1; then
  installed_k3s="$(k3s --version | awk 'NR==1 {print $3}')"
  [[ "${installed_k3s}" == "${K3S_VERSION}" ]] || fail "K3s ${installed_k3s} is already installed; expected ${K3S_VERSION}"
  log "K3s ${K3S_VERSION} is already installed"
else
  log "Installing K3s ${K3S_VERSION} without Traefik"
  installer="$(mktemp)"
  trap 'rm -f "${installer:-}"' EXIT
  curl -fsSL https://get.k3s.io -o "${installer}"
  chmod 700 "${installer}"
  INSTALL_K3S_VERSION="${K3S_VERSION}" \
    INSTALL_K3S_EXEC="server --disable traefik" \
    "${installer}"
  rm -f "${installer}"
  trap - EXIT
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl wait --for=condition=Ready node --all --timeout=180s
kubectl get storageclass local-path >/dev/null

if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  target_home="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
  target_group="$(id -gn "${SUDO_USER}")"
  [[ -n "${target_home}" ]] || fail "Could not resolve home directory for ${SUDO_USER}"
  install -d -m 0700 -o "${SUDO_USER}" -g "${target_group}" "${target_home}/.kube"
  install -m 0600 -o "${SUDO_USER}" -g "${target_group}" /etc/rancher/k3s/k3s.yaml "${target_home}/.kube/config"
  log "Installed a mode-0600 kubeconfig for ${SUDO_USER}"
fi

if command -v helm >/dev/null 2>&1; then
  log "Helm $(helm version --short) is already installed"
else
  log "Installing Helm ${HELM_VERSION} with published checksum verification"
  helm_tmp="$(mktemp -d)"
  trap 'rm -rf "${helm_tmp:-}"' EXIT
  archive="helm-${HELM_VERSION}-linux-${helm_arch}.tar.gz"
  curl -fsSLo "${helm_tmp}/${archive}" "https://get.helm.sh/${archive}"
  curl -fsSLo "${helm_tmp}/${archive}.sha256sum" "https://get.helm.sh/${archive}.sha256sum"
  (
    cd "${helm_tmp}"
    sha256sum -c "${archive}.sha256sum"
    tar -xzf "${archive}"
    install -m 0755 "linux-${helm_arch}/helm" /usr/local/bin/helm
  )
  rm -rf "${helm_tmp}"
  trap - EXIT
fi

log "Bootstrap complete"
sysctl vm.max_map_count
kubectl get nodes -o wide
kubectl get storageclass

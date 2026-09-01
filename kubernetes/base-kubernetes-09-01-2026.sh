#!/usr/bin/env bash

################################################################################
# Kubernetes Debian Host Preparation Script
#
# Purpose:
#   Prepares a Debian-based host for Kubernetes using kubeadm and validates the
#   host for either a traditional iptables dataplane or a Calico eBPF dataplane.
#
# Important:
#   - This script does not run kubeadm init or kubeadm join.
#   - This script does not install a Kubernetes CNI.
#   - This script does not enable Calico eBPF by itself.
#   - The script configures containerd as a Kubernetes-compatible CRI runtime.
#
# Intended environment:
#   - Debian or Debian-based Linux distribution
#   - kubeadm-managed Kubernetes cluster
#   - containerd container runtime
#   - Optional Calico Operator installation with eBPF
################################################################################

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

########################################
# Configuration Variables
########################################

# Kubernetes minor-version repository.
#
# Use v1.36 until all required dependency packages are available in v1.37.
K8S_VERSION="v1.36"

K8S_REPO_URL="https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/"
K8S_RELEASE_KEY_URL="${K8S_REPO_URL}Release.key"
DOCKER_REPO_URL="https://download.docker.com/linux/debian"

K8S_KEYRING="/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
DOCKER_KEYRING="/etc/apt/keyrings/docker.asc"
K8S_APT_LIST="/etc/apt/sources.list.d/kubernetes.list"
DOCKER_APT_SOURCES="/etc/apt/sources.list.d/docker.sources"

CONTAINERD_CONFIG="/etc/containerd/config.toml"
CONTAINERD_SOCKET="/run/containerd/containerd.sock"
CRICTL_CONFIG="/etc/crictl.yaml"

# Supported values:
#   ebpf
#   iptables
DATAPLANE_TARGET="ebpf"

# Calico eBPF requires Linux 5.10 or newer on generic supported distributions.
EBPF_MIN_KERNEL="5.10"

# Regenerate the containerd configuration from the installed containerd
# version. The existing configuration is backed up first.
#
# Recommended value for initial Kubernetes host preparation: true
#
# Set to false only when you intentionally maintain a customized and already
# validated Kubernetes-compatible containerd configuration.
REGENERATE_CONTAINERD_CONFIG="true"

# Configure and enable UFW.
CONFIGURE_UFW="true"

# Permit the Kubernetes default NodePort range.
ALLOW_NODEPORTS="true"

# Permit Calico BGP.
ALLOW_CALICO_BGP="true"

# Permit Calico VXLAN.
ALLOW_CALICO_VXLAN="true"

# Permit Calico Typha.
# Operator-based Calico installations include Typha.
ALLOW_CALICO_TYPHA="true"

########################################
# Runtime Variables
########################################

BPF_PROBE_FILE=""
CONTAINERD_BACKUP=""
CONTAINERD_CONFIG_VERSION="unknown"
KERNEL_VERSION=""
CGROUP_FS=""
TIME_SYNC_STATUS="unknown"

########################################
# Helper Functions
########################################

log() {
    printf '\n--- %s ---\n' "$*"
}

pass() {
    printf 'PASS: %s\n' "$*"
}

info() {
    printf 'INFO: %s\n' "$*"
}

warn() {
    printf 'WARN: %s\n' "$*" >&2
}

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

version_ge() {
    dpkg --compare-versions "$1" ge "$2"
}

module_loaded() {
    lsmod | awk 'NR > 1 {print $1}' | grep -qx "$1"
}

validate_boolean() {
    local variable_name="$1"
    local variable_value="$2"

    case "${variable_value}" in
        true|false)
            ;;
        *)
            fail "${variable_name} must be either 'true' or 'false'."
            ;;
    esac
}

on_error() {
    local exit_code=$?
    local line_number="${BASH_LINENO-unknown}"
    local command_name="${BASH_COMMAND:-unknown}"

    printf '\nERROR: Script failed at line %s while running: %s\n' \
        "${line_number}" \
        "${command_name}" >&2

    exit "${exit_code}"
}

cleanup() {
    if [[ -n "${BPF_PROBE_FILE}" && -f "${BPF_PROBE_FILE}" ]]; then
        rm -f "${BPF_PROBE_FILE}"
    fi
}

trap on_error ERR
trap cleanup EXIT

########################################
# Banner and Preconditions
########################################

echo "=================================================="
echo " Kubernetes Debian Host Preparation Script"
echo " Kubernetes Repository Version: ${K8S_VERSION}"
echo " Dataplane Validation Target : ${DATAPLANE_TARGET}"
echo "=================================================="

[[ "${EUID}" -eq 0 ]] ||
    fail "Run this script as root or with sudo."

[[ -f /etc/os-release ]] ||
    fail "/etc/os-release was not found."

case "${DATAPLANE_TARGET}" in
    ebpf|iptables)
        ;;
    *)
        fail "DATAPLANE_TARGET must be either 'ebpf' or 'iptables'."
        ;;
esac

validate_boolean \
    "REGENERATE_CONTAINERD_CONFIG" \
    "${REGENERATE_CONTAINERD_CONFIG}"

validate_boolean "CONFIGURE_UFW" "${CONFIGURE_UFW}"
validate_boolean "ALLOW_NODEPORTS" "${ALLOW_NODEPORTS}"
validate_boolean "ALLOW_CALICO_BGP" "${ALLOW_CALICO_BGP}"
validate_boolean "ALLOW_CALICO_VXLAN" "${ALLOW_CALICO_VXLAN}"
validate_boolean "ALLOW_CALICO_TYPHA" "${ALLOW_CALICO_TYPHA}"

# shellcheck source=/dev/null
. /etc/os-release

if [[ "${ID}" != "debian" && "${ID_LIKE:-}" != *"debian"* ]]; then
    warn "Designed for Debian-based systems; detected ${PRETTY_NAME}."
fi

[[ -n "${VERSION_CODENAME:-}" ]] ||
    fail "VERSION_CODENAME is missing from /etc/os-release."

echo "Detected OS       : ${PRETTY_NAME}"
echo "Detected Codename : ${VERSION_CODENAME}"
echo "Detected Kernel   : $(uname -r)"
echo "Detected Hostname : $(hostname)"

########################################
# Install Base Dependencies
########################################

log "Installing base dependencies"

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install -y \
    apt-transport-https \
    bash-completion \
    ca-certificates \
    conntrack \
    curl \
    dnsutils \
    gnupg \
    htop \
    iproute2 \
    iptables \
    jq \
    kmod \
    net-tools \
    nftables \
    socat \
    ufw \
    vim \
    wget

if [[ "${DATAPLANE_TARGET}" == "ebpf" ]]; then
    apt-get install -y bpftool
fi

########################################
# Time Synchronization Validation
########################################

log "Validating time synchronization"

if ! command_exists timedatectl; then
    warn "timedatectl is unavailable; time synchronization cannot be validated."
else
    NTP_SYNCHRONIZED="$(
        timedatectl show \
            --property=NTPSynchronized \
            --value 2>/dev/null || true
    )"

    NTP_ENABLED="$(
        timedatectl show \
            --property=NTP \
            --value 2>/dev/null || true
    )"

    TIMEZONE="$(
        timedatectl show \
            --property=Timezone \
            --value 2>/dev/null || true
    )"

    if [[ "${NTP_SYNCHRONIZED}" == "yes" ]]; then
        TIME_SYNC_STATUS="synchronized"
        pass "System clock is synchronized."
    else
        TIME_SYNC_STATUS="not confirmed"
        warn "System clock synchronization is not currently confirmed."
        warn "Verify NTP before running kubeadm init or kubeadm join."
    fi

    if [[ "${NTP_ENABLED}" == "yes" ]]; then
        pass "An NTP synchronization service is active."
    else
        warn "An active NTP synchronization service was not confirmed."
    fi

    info "Current system time: $(date --iso-8601=seconds)"
    info "Configured timezone: ${TIMEZONE:-unknown}"

    timedatectl status || true
fi

########################################
# Configure Kubernetes Repository
########################################

log "Configuring Kubernetes repository ${K8S_VERSION}"

install -d -m 0755 /etc/apt/keyrings

K8S_KEY_TEMP="$(mktemp)"

curl -fsSL "${K8S_RELEASE_KEY_URL}" |
    gpg --dearmor > "${K8S_KEY_TEMP}"

install -m 0644 "${K8S_KEY_TEMP}" "${K8S_KEYRING}"
rm -f "${K8S_KEY_TEMP}"

cat > "${K8S_APT_LIST}" <<EOF
deb [signed-by=${K8S_KEYRING}] ${K8S_REPO_URL} /
EOF

chmod 0644 "${K8S_APT_LIST}"

########################################
# Configure Docker Repository
########################################

log "Configuring Docker repository for containerd.io"

DOCKER_KEY_TEMP="$(mktemp)"

curl -fsSL "${DOCKER_REPO_URL}/gpg" > "${DOCKER_KEY_TEMP}"

install -m 0644 "${DOCKER_KEY_TEMP}" "${DOCKER_KEYRING}"
rm -f "${DOCKER_KEY_TEMP}"

cat > "${DOCKER_APT_SOURCES}" <<EOF
Types: deb
URIs: ${DOCKER_REPO_URL}
Suites: ${VERSION_CODENAME}
Components: stable
Signed-By: ${DOCKER_KEYRING}
EOF

chmod 0644 "${DOCKER_APT_SOURCES}"

########################################
# Validate Kubernetes Package Repository
########################################

log "Validating Kubernetes package availability"

apt-get update

REQUIRED_KUBERNETES_PACKAGES=(
    kubelet
    kubeadm
    kubectl
    cri-tools
    kubernetes-cni
)

MISSING_KUBERNETES_PACKAGES=()

for package_name in "${REQUIRED_KUBERNETES_PACKAGES[@]}"; do
    package_candidate="$(
        apt-cache policy "${package_name}" |
        awk '/Candidate:/ {print $2}'
    )"

    if [[ -z "${package_candidate}" ||
          "${package_candidate}" == "(none)" ]]; then

        MISSING_KUBERNETES_PACKAGES+=("${package_name}")
    else
        info "${package_name} candidate: ${package_candidate}"
    fi
done

if [[ "${#MISSING_KUBERNETES_PACKAGES[@]}" -gt 0 ]]; then
    printf '\n' >&2
    printf 'The following required packages have no installation candidate:\n' >&2

    printf '  %s\n' "${MISSING_KUBERNETES_PACKAGES[@]}" >&2

    printf '\n' >&2
    printf 'The selected Kubernetes repository may be incomplete.\n' >&2
    printf 'Selected repository: %s\n' "${K8S_REPO_URL}" >&2
    printf 'Try a previous supported Kubernetes minor version.\n' >&2

    fail "Kubernetes repository package validation failed."
fi

pass "All required Kubernetes packages have installation candidates."

########################################
# Install Kubernetes and Runtime
########################################

log "Installing kubelet, kubeadm, kubectl, containerd.io, and CRI tools"

if ! apt-get install -y \
    kubelet \
    kubeadm \
    kubectl \
    containerd.io \
    cri-tools \
    kubernetes-cni; then

    fail "Kubernetes package installation failed."
fi

# Hold Kubernetes components so upgrades occur intentionally through the
# documented kubeadm upgrade workflow.
#
# containerd.io is intentionally not held so it can receive runtime and
# security updates.
apt-mark hold kubelet kubeadm kubectl

########################################
# Disable Swap
########################################

log "Disabling swap"

swapoff -a

if grep -qE \
    '^[[:space:]]*[^#].*[[:space:]]swap[[:space:]]' \
    /etc/fstab; then

    FSTAB_BACKUP="/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
    cp -a /etc/fstab "${FSTAB_BACKUP}"

    sed -ri \
        '/^[[:space:]]*[^#].*[[:space:]]swap[[:space:]]/s/^/#/' \
        /etc/fstab

    info "Backed up /etc/fstab to ${FSTAB_BACKUP}."
fi

if swapon --show --noheadings | grep -q .; then
    fail "Swap remains active."
fi

pass "Swap is disabled."

########################################
# Kernel Modules
########################################

log "Configuring Kubernetes kernel modules"

cat > /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
nf_conntrack
EOF

for module in overlay br_netfilter nf_conntrack; do
    modprobe "${module}"
done

for module in overlay br_netfilter nf_conntrack; do
    if module_loaded "${module}"; then
        pass "Kernel module loaded: ${module}"
    else
        fail "Kernel module failed to load: ${module}"
    fi
done

########################################
# Sysctl Configuration
########################################

log "Configuring Kubernetes networking sysctls"

cat > /etc/sysctl.d/99-kubernetes.conf <<'EOF'
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system >/dev/null

########################################
# Prepare BPF Filesystem
########################################

if [[ "${DATAPLANE_TARGET}" == "ebpf" ]]; then
    log "Preparing the BPF filesystem"

    install -d -m 0755 /sys/fs/bpf

    if ! mountpoint -q /sys/fs/bpf; then
        mount -t bpf bpffs /sys/fs/bpf
    fi

    if ! grep -Eq \
        '^[^#]+[[:space:]]+/sys/fs/bpf[[:space:]]+bpf[[:space:]]' \
        /etc/fstab; then

        printf 'bpffs /sys/fs/bpf bpf defaults 0 0\n' >> /etc/fstab
    fi
else
    info "Skipping explicit bpffs preparation because iptables is selected."
fi

########################################
# Configure containerd
########################################

log "Configuring containerd for Kubernetes CRI"

install -d -m 0755 /etc/containerd

if [[ -s "${CONTAINERD_CONFIG}" ]]; then
    CONTAINERD_BACKUP="$(
        printf '%s.bak.%s' \
            "${CONTAINERD_CONFIG}" \
            "$(date +%Y%m%d%H%M%S)"
    )"

    cp -a "${CONTAINERD_CONFIG}" "${CONTAINERD_BACKUP}"

    info "Existing containerd configuration backed up."
    info "Backup created: ${CONTAINERD_BACKUP}"
fi

if [[ "${REGENERATE_CONTAINERD_CONFIG}" == "true" ]]; then
    info "Generating a clean configuration from the installed containerd version."

    CONTAINERD_TEMP_CONFIG="$(mktemp)"

    containerd config default > "${CONTAINERD_TEMP_CONFIG}"

    if [[ ! -s "${CONTAINERD_TEMP_CONFIG}" ]]; then
        rm -f "${CONTAINERD_TEMP_CONFIG}"
        fail "containerd generated an empty configuration."
    fi

    install -m 0644 \
        "${CONTAINERD_TEMP_CONFIG}" \
        "${CONTAINERD_CONFIG}"

    rm -f "${CONTAINERD_TEMP_CONFIG}"
else
    if [[ ! -s "${CONTAINERD_CONFIG}" ]]; then
        containerd config default > "${CONTAINERD_CONFIG}"
        chmod 0644 "${CONTAINERD_CONFIG}"

        info "No existing containerd configuration was found."
        info "Generated a clean default configuration."
    else
        info "Preserving the existing containerd configuration."
    fi
fi

########################################
# Detect containerd Configuration Version
########################################

CONTAINERD_CONFIG_VERSION="$(
    awk '
        /^[[:space:]]*version[[:space:]]*=/ {
            gsub(/[[:space:]]/, "", $0)
            split($0, fields, "=")
            print fields[2]
            exit
        }
    ' "${CONTAINERD_CONFIG}"
)"

if [[ -z "${CONTAINERD_CONFIG_VERSION}" ]]; then
    CONTAINERD_CONFIG_VERSION="legacy"
fi

info "Detected containerd configuration version: ${CONTAINERD_CONFIG_VERSION}"

if [[ "${CONTAINERD_CONFIG_VERSION}" == "legacy" ]]; then
    fail "A legacy containerd configuration was detected after configuration generation."
fi

########################################
# Ensure CRI Is Not Disabled
########################################

log "Validating containerd CRI plugin configuration"

if grep -Eq \
    '^[[:space:]]*disabled_plugins[[:space:]]*=.*["'\'']cri["'\'']' \
    "${CONTAINERD_CONFIG}"; then

    if [[ "${REGENERATE_CONTAINERD_CONFIG}" == "true" ]]; then
        fail "The generated containerd configuration unexpectedly disables CRI."
    else
        fail "CRI is disabled in ${CONTAINERD_CONFIG}. Remove cri from disabled_plugins or enable configuration regeneration."
    fi
fi

pass "The containerd CRI plugin is not disabled."

########################################
# Enable the systemd Cgroup Driver
########################################

log "Configuring containerd systemd cgroup support"

if grep -Eq \
    'SystemdCgroup[[:space:]]*=[[:space:]]*false' \
    "${CONTAINERD_CONFIG}"; then

    sed -Ei \
        's/SystemdCgroup[[:space:]]*=[[:space:]]*false/SystemdCgroup = true/g' \
        "${CONTAINERD_CONFIG}"
fi

if ! grep -Eq \
    'SystemdCgroup[[:space:]]*=[[:space:]]*true' \
    "${CONTAINERD_CONFIG}"; then

    fail "Unable to verify SystemdCgroup = true in ${CONTAINERD_CONFIG}."
fi

pass "containerd is configured to use the systemd cgroup driver."

########################################
# Validate containerd Configuration
########################################

log "Validating containerd configuration syntax"

if containerd config dump \
    --config "${CONTAINERD_CONFIG}" \
    >/dev/null 2>&1; then

    pass "containerd configuration syntax is valid."
else
    warn "containerd config dump with --config was unsuccessful."
    info "Trying standard containerd configuration validation."

    if containerd config dump >/dev/null 2>&1; then
        pass "containerd configuration can be parsed."
    else
        fail "containerd cannot parse ${CONTAINERD_CONFIG}."
    fi
fi

########################################
# Start containerd
########################################

log "Starting containerd"

systemctl daemon-reload
systemctl enable containerd
systemctl restart containerd

if systemctl is-active --quiet containerd; then
    pass "containerd is active."
else
    systemctl status containerd --no-pager --full || true
    journalctl -u containerd --no-pager -n 100 || true

    fail "containerd failed to start."
fi

########################################
# Verify containerd Plugins
########################################

log "Checking containerd CRI plugin status"

CONTAINERD_CRI_PLUGIN_OUTPUT="$(
    ctr plugins list 2>/dev/null |
    awk '
        $1 ~ /io.containerd.grpc.v1/ && $2 == "cri" {
            print
        }

        $1 ~ /io.containerd.cri.v1/ {
            print
        }
    '
)"

if [[ -n "${CONTAINERD_CRI_PLUGIN_OUTPUT}" ]]; then
    info "Detected containerd CRI plugin entries:"
    printf '%s\n' "${CONTAINERD_CRI_PLUGIN_OUTPUT}" |
        sed 's/^/  /'
fi

if ctr plugins list 2>/dev/null |
   grep -E 'io\.containerd\.(grpc\.v1|cri\.v1).*[[:space:]]ok([[:space:]]|$)' \
   >/dev/null; then

    pass "containerd reports a healthy CRI plugin."
else
    warn "The CRI plugin was not identified as healthy through ctr output."
    warn "The definitive crictl validation will run next."
fi

########################################
# Configure crictl
########################################

log "Configuring crictl"

cat > "${CRICTL_CONFIG}" <<EOF
runtime-endpoint: unix://${CONTAINERD_SOCKET}
image-endpoint: unix://${CONTAINERD_SOCKET}
timeout: 10
debug: false
EOF

chmod 0644 "${CRICTL_CONFIG}"

########################################
# Validate CRI v1
########################################

log "Validating the containerd CRI v1 runtime API"

if crictl info >/dev/null 2>&1; then
    pass "crictl can communicate with the containerd CRI runtime."
else
    warn "crictl could not communicate with containerd."

    info "containerd service status:"
    systemctl status containerd --no-pager --full || true

    info "Recent containerd logs:"
    journalctl -u containerd --no-pager -n 100 || true

    info "containerd plugin status:"
    ctr plugins list || true

    fail "containerd is not exposing a working CRI v1 RuntimeService."
fi

CRI_RUNTIME_NAME="$(
    crictl info 2>/dev/null |
    jq -r '.config.containerd.defaultRuntimeName // empty' \
    2>/dev/null || true
)"

if [[ -n "${CRI_RUNTIME_NAME}" ]]; then
    info "Default containerd CRI runtime: ${CRI_RUNTIME_NAME}"
fi

########################################
# Enable kubelet
########################################

log "Enabling kubelet"

systemctl enable kubelet

if systemctl is-enabled --quiet kubelet; then
    pass "kubelet is enabled."
else
    fail "kubelet could not be enabled."
fi

# kubelet is expected to restart or remain inactive before kubeadm init or join
# creates /var/lib/kubelet/config.yaml.
if systemctl is-active --quiet kubelet; then
    info "kubelet is currently active."
else
    info "kubelet is not active yet, which is normal before kubeadm init or join."
fi

########################################
# Configure kubectl Completion
########################################

log "Configuring kubectl Bash completion"

install -d -m 0755 /etc/bash_completion.d

kubectl completion bash > /etc/bash_completion.d/kubectl
chmod 0644 /etc/bash_completion.d/kubectl

cat > /etc/profile.d/kubectl-alias.sh <<'EOF'
alias k=kubectl

if declare -F __start_kubectl >/dev/null 2>&1; then
    complete -o default -F __start_kubectl k
fi
EOF

chmod 0644 /etc/profile.d/kubectl-alias.sh

########################################
# UFW Configuration
########################################

if [[ "${CONFIGURE_UFW}" == "true" ]]; then
    log "Configuring UFW"

    if grep -q '^DEFAULT_FORWARD_POLICY=' /etc/default/ufw; then
        sed -i \
            's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' \
            /etc/default/ufw
    else
        printf '%s\n' \
            'DEFAULT_FORWARD_POLICY="ACCEPT"' >> /etc/default/ufw
    fi

    # Common Kubernetes ports.
    ufw allow 22/tcp comment "SSH"
    ufw allow 6443/tcp comment "Kubernetes API Server"
    ufw allow 2379:2380/tcp comment "Kubernetes etcd"
    ufw allow 10250/tcp comment "Kubelet API"
    ufw allow 10257/tcp comment "Kube Controller Manager"
    ufw allow 10259/tcp comment "Kube Scheduler"

    # Calico BGP.
    if [[ "${ALLOW_CALICO_BGP}" == "true" ]]; then
        ufw allow 179/tcp comment "Calico BGP"
    fi

    # Calico VXLAN and eBPF overlay communication.
    if [[ "${ALLOW_CALICO_VXLAN}" == "true" ]]; then
        ufw allow 4789/udp comment "Calico VXLAN and eBPF overlay"
    fi

    # Calico Typha.
    if [[ "${ALLOW_CALICO_TYPHA}" == "true" ]]; then
        ufw allow 5473/tcp comment "Calico Typha"
    fi

    # Kubernetes NodePort Services.
    if [[ "${ALLOW_NODEPORTS}" == "true" ]]; then
        ufw allow 30000:32767/tcp comment "Kubernetes NodePort TCP"
        ufw allow 30000:32767/udp comment "Kubernetes NodePort UDP"
    fi

    ufw --force enable
    ufw reload

    warn "UFW rules are intentionally broad for reusable lab deployments."
    warn "Restrict source networks and apply role-specific rules in production."
    warn "If using Calico IP-in-IP, permit IP protocol 4 between cluster nodes."
else
    info "Skipping UFW configuration because CONFIGURE_UFW=false."
fi

########################################
# Common Validation
########################################

log "Running common Kubernetes host validation"

if swapon --show --noheadings | grep -q .; then
    fail "Swap remains active."
else
    pass "Swap is disabled."
fi

[[ "$(sysctl -n net.ipv4.ip_forward)" == "1" ]] ||
    fail "net.ipv4.ip_forward is not enabled."

[[ "$(sysctl -n net.bridge.bridge-nf-call-iptables)" == "1" ]] ||
    fail "net.bridge.bridge-nf-call-iptables is not enabled."

[[ "$(sysctl -n net.bridge.bridge-nf-call-ip6tables)" == "1" ]] ||
    fail "net.bridge.bridge-nf-call-ip6tables is not enabled."

pass "Required Kubernetes networking sysctls are enabled."

systemctl is-active --quiet containerd ||
    fail "containerd is not active."

systemctl is-enabled --quiet containerd ||
    fail "containerd is not enabled."

systemctl is-enabled --quiet kubelet ||
    fail "kubelet is not enabled."

pass "containerd is active and kubelet/containerd are enabled."

crictl info >/dev/null 2>&1 ||
    fail "crictl cannot communicate with containerd."

pass "The containerd CRI v1 API is operational."

########################################
# Cgroup Validation
########################################

log "Checking cgroup configuration"

CGROUP_FS="$(stat -fc %T /sys/fs/cgroup)"
info "Detected cgroup filesystem: ${CGROUP_FS}"

case "${CGROUP_FS}" in
    cgroup2fs)
        pass "Unified cgroup v2 is active."
        ;;
    tmpfs)
        warn "Legacy or hybrid cgroup mode appears to be active."
        warn "Modern Debian Kubernetes deployments normally use cgroup v2."
        ;;
    *)
        warn "Unexpected cgroup filesystem detected: ${CGROUP_FS}"
        ;;
esac

if grep -Eq \
    'SystemdCgroup[[:space:]]*=[[:space:]]*true' \
    "${CONTAINERD_CONFIG}"; then

    pass "containerd systemd cgroup configuration is present."
else
    fail "containerd is not configured with SystemdCgroup = true."
fi

########################################
# iptables Readiness
########################################

log "Checking iptables readiness"

command_exists iptables ||
    fail "iptables is not installed."

iptables --version

iptables -t filter -S >/dev/null ||
    fail "Unable to read the iptables filter table."

iptables -t nat -S >/dev/null ||
    fail "Unable to read the iptables NAT table."

pass "iptables userspace and kernel tables are operational."

########################################
# eBPF Readiness
########################################

if [[ "${DATAPLANE_TARGET}" == "ebpf" ]]; then
    log "Checking eBPF readiness"

    KERNEL_VERSION="$(uname -r | sed 's/-.*//')"

    if version_ge "${KERNEL_VERSION}" "${EBPF_MIN_KERNEL}"; then
        pass "Kernel ${KERNEL_VERSION} meets the Calico eBPF minimum ${EBPF_MIN_KERNEL}."
    else
        fail "Kernel ${KERNEL_VERSION} is below the Calico eBPF minimum ${EBPF_MIN_KERNEL}."
    fi

    mountpoint -q /sys/fs/bpf ||
        fail "/sys/fs/bpf is not mounted."

    [[ "$(stat -fc %T /sys/fs/bpf)" == "bpf_fs" ]] ||
        fail "/sys/fs/bpf is not a BPF filesystem."

    pass "bpffs is mounted at /sys/fs/bpf."

    command_exists bpftool ||
        fail "bpftool is not installed."

    BPF_PROBE_FILE="$(mktemp)"

    if bpftool feature probe kernel > "${BPF_PROBE_FILE}" 2>&1; then
        pass "bpftool kernel feature probe completed successfully."
    else
        cat "${BPF_PROBE_FILE}" >&2
        fail "bpftool kernel feature probe failed."
    fi

    if grep -q 'CONFIG_BPF=y' "${BPF_PROBE_FILE}" ||
       grep -q 'bpf() syscall is available' "${BPF_PROBE_FILE}"; then

        pass "Kernel reports BPF support."
    else
        warn "The probe did not explicitly report CONFIG_BPF=y."
        warn "Review the bpftool output if Calico eBPF fails."
    fi

    rm -f "${BPF_PROBE_FILE}"
    BPF_PROBE_FILE=""
else
    info "Skipping Calico eBPF validation because iptables is selected."
fi

########################################
# UFW Validation
########################################

if [[ "${CONFIGURE_UFW}" == "true" ]]; then
    log "Validating UFW configuration"

    ufw status | grep -q '^Status: active' ||
        fail "UFW is not active."

    ufw status | grep -Eq '(^|[[:space:]])6443/tcp' ||
        fail "Kubernetes API server UFW rule is missing."

    ufw status | grep -Eq '(^|[[:space:]])10250/tcp' ||
        fail "Kubelet API UFW rule is missing."

    if [[ "${ALLOW_CALICO_BGP}" == "true" ]]; then
        ufw status | grep -Eq '(^|[[:space:]])179/tcp' ||
            fail "Calico BGP UFW rule is missing."
    fi

    if [[ "${ALLOW_CALICO_VXLAN}" == "true" ]]; then
        ufw status | grep -Eq '(^|[[:space:]])4789/udp' ||
            fail "Calico VXLAN UFW rule is missing."
    fi

    if [[ "${ALLOW_CALICO_TYPHA}" == "true" ]]; then
        ufw status | grep -Eq '(^|[[:space:]])5473/tcp' ||
            fail "Calico Typha UFW rule is missing."
    fi

    if [[ "${ALLOW_NODEPORTS}" == "true" ]]; then
        ufw status | grep -Eq '30000:32767/tcp' ||
            fail "Kubernetes NodePort TCP UFW rule is missing."

        ufw status | grep -Eq '30000:32767/udp' ||
            fail "Kubernetes NodePort UDP UFW rule is missing."
    fi

    pass "Required UFW rules are present."
fi

########################################
# Installed Versions
########################################

log "Installed component versions"

kubeadm version || true
kubectl version --client || true
kubelet --version || true
containerd --version || true
runc --version | head -n 1 || true
crictl --version || true
iptables --version || true

if [[ "${DATAPLANE_TARGET}" == "ebpf" ]]; then
    bpftool version || true
fi

########################################
# Final CRI Validation
########################################

log "Running final CRI validation"

if crictl info >/dev/null 2>&1; then
    pass "containerd CRI runtime validation passed."
else
    fail "Final crictl validation failed."
fi

info "CRI runtime version:"
crictl version || true

########################################
# UFW Status
########################################

if [[ "${CONFIGURE_UFW}" == "true" ]]; then
    log "UFW status"
    ufw status verbose || true
fi

########################################
# Summary
########################################

echo
echo "=================================================="
echo " Kubernetes Host Ready"
echo "=================================================="
echo "Hostname          : $(hostname)"
echo "OS                : ${PRETTY_NAME}"
echo "Kernel            : $(uname -r)"
echo "Kubernetes Repo   : ${K8S_VERSION}"
echo "Dataplane Target  : ${DATAPLANE_TARGET}"
echo "Container Runtime : $(containerd --version 2>/dev/null || echo unknown)"
echo "Containerd Config : version ${CONTAINERD_CONFIG_VERSION}"
echo "CRI Socket        : unix://${CONTAINERD_SOCKET}"
echo "Cgroup Filesystem : ${CGROUP_FS}"
echo "Time Sync Status  : ${TIME_SYNC_STATUS}"
echo "UFW Configured    : ${CONFIGURE_UFW}"

if [[ -n "${CONTAINERD_BACKUP}" ]]; then
    echo "Containerd Backup : ${CONTAINERD_BACKUP}"
fi

echo
echo "Containerd validation:"
echo "  CRI plugin       : enabled"
echo "  CRI v1 API       : operational"
echo "  SystemdCgroup    : true"
echo
echo "The host is ready for kubeadm init or kubeadm join."
echo
echo "Example control-plane initialization:"
echo
echo "  sudo kubeadm init \\"
echo "    --pod-network-cidr=172.16.0.0/16 \\"
echo "    --cri-socket=unix://${CONTAINERD_SOCKET}"
echo
echo "Important Calico eBPF next step:"

if [[ "${DATAPLANE_TARGET}" == "ebpf" ]]; then
    echo "  Install Calico through the Tigera Operator."
    echo
    echo "  Configure the Installation resource with:"
    echo "    linuxDataplane: BPF"
    echo "    bpfNetworkBootstrap: Enabled"
    echo "    kubeProxyManagement: Enabled"
else
    echo "  Install the selected CNI in its standard iptables dataplane mode."
fi

echo
echo "Firewall notes:"

if [[ "${ALLOW_CALICO_TYPHA}" == "true" ]]; then
    echo "  TCP 5473 is enabled for Calico Typha."
fi

if [[ "${ALLOW_CALICO_VXLAN}" == "true" ]]; then
    echo "  UDP 4789 is enabled for Calico VXLAN."
fi

if [[ "${ALLOW_CALICO_BGP}" == "true" ]]; then
    echo "  TCP 179 is enabled for Calico BGP."
fi

if [[ "${ALLOW_NODEPORTS}" == "true" ]]; then
    echo "  TCP/UDP 30000-32767 are enabled for NodePort Services."
fi

echo
echo "This script does not initialize Kubernetes or install the CNI."
echo
echo "Validation Status: PASS"
echo "=================================================="

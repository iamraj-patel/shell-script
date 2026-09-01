#!/usr/bin/env bash

################################################################################
# Kubernetes Cluster Health Auditor
#
# Purpose:
#   Performs a practical health audit of a kubeadm-based Kubernetes cluster.
#
# Features:
#   - Kubernetes API connectivity and /livez /readyz validation
#   - JSON-based node, pod and container health evaluation
#   - Node pressure, NetworkUnavailable and taint checks
#   - Pod restart threshold evaluation
#   - CoreDNS and in-cluster DNS testing
#   - EndpointSlice-based Service backend validation
#   - Pod-to-Service networking smoke test
#   - PVC and StorageClass validation
#   - Time-bounded Kubernetes Warning event filtering
#   - Tigera and Calico node health validation
#   - Calico eBPF configuration and runtime validation
#   - kube-proxy replacement validation
#   - Local system time synchronization validation
#   - Local container runtime validation with crictl
#   - Metrics API validation
#   - Unique smoke-test resource names
#   - Reliable cleanup on success, error or interruption
#   - Structured PASS, WARN, FAIL and SKIP summary
#
# Requirements:
#   - bash
#   - kubectl
#   - jq
#
# Optional:
#   - crictl
#   - sudo
#   - timedatectl
#
# Notes:
#   - Temporary Pods, Services and namespaces are created for smoke testing.
#   - All temporary resources are deleted automatically.
#   - Existing cluster workloads are not modified.
################################################################################

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

########################################
# Configuration
########################################

RESTART_WARN_THRESHOLD=5
RESTART_FAIL_THRESHOLD=15

# Only Warning events newer than this value are reported.
EVENT_LOOKBACK_MINUTES=60
MAX_WARNING_EVENTS=25

DNS_TIMEOUT_SECONDS=90
POD_TIMEOUT_SECONDS=120
CONNECTIVITY_TIMEOUT_SECONDS=120
RESOURCE_DELETE_TIMEOUT_SECONDS=60

DNS_TEST_IMAGE="busybox:1.36"
CURL_TEST_IMAGE="curlimages/curl:latest"
NGINX_TEST_IMAGE="nginx:alpine"

# Run temporary DNS and Pod-to-Service networking tests.
RUN_SMOKE_TESTS="true"

# Check the local audit host time synchronization using timedatectl.
CHECK_LOCAL_TIME_SYNC="true"

# Check the local audit host container runtime using crictl.
CHECK_LOCAL_CRI="true"

# Set to false if an absent Metrics Server should be reported as SKIP.
METRICS_SERVER_MISSING_IS_WARNING="true"

# Number of recent calico-node log lines to inspect.
CALICO_LOG_TAIL_LINES=1000

########################################
# Counters
########################################

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

########################################
# Runtime Variables
########################################

START_EPOCH="$(date +%s)"
START_TIME="$(date --iso-8601=seconds 2>/dev/null || date)"

RUN_SUFFIX="$(
    printf '%s-%s-%s' \
        "$(date +%m%d%H%M%S)" \
        "$$" \
        "${RANDOM}"
)"

# Keep names within the Kubernetes DNS label length limit.
SMOKE_NAMESPACE="cluster-health-${RUN_SUFFIX}"
DNS_TEST_POD="dns-test-${RUN_SUFFIX}"
NGINX_TEST_POD="nginx-test-${RUN_SUFFIX}"
NGINX_TEST_SERVICE="nginx-svc-${RUN_SUFFIX}"
CURL_TEST_POD="curl-test-${RUN_SUFFIX}"

SMOKE_NAMESPACE_CREATED="false"
DNS_TEST_POD_CREATED="false"
CLEANUP_STARTED="false"

ENDPOINTSLICE_AVAILABLE="false"
CALICO_PRESENT="false"
CALICO_EBPF_CONFIGURED="false"
CALICO_NODE_COUNT=0

CURRENT_CONTEXT=""

TEMP_DIR="$(mktemp -d -t k8s-health-audit.XXXXXX)"

NODE_JSON="${TEMP_DIR}/nodes.json"
POD_JSON="${TEMP_DIR}/pods.json"
SERVICE_JSON="${TEMP_DIR}/services.json"
ENDPOINTSLICE_JSON="${TEMP_DIR}/endpointslices.json"
EVENT_JSON="${TEMP_DIR}/events.json"
PVC_JSON="${TEMP_DIR}/pvcs.json"

########################################
# Output Helpers
########################################

print_header() {
    printf '\n'
    printf '%s\n' "=================================================="
    printf '%s\n' "$1"
    printf '%s\n' "=================================================="
}

print_section() {
    printf '\n[%s] %s\n' "$1" "$2"
}

pass() {
    printf '  [PASS] %s\n' "$1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

warn() {
    printf '  [WARN] %s\n' "$1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

fail() {
    printf '  [FAIL] %s\n' "$1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

skip() {
    printf '  [SKIP] %s\n' "$1"
    SKIP_COUNT=$((SKIP_COUNT + 1))
}

info() {
    printf '  [INFO] %s\n' "$1"
}

indent_output() {
    sed 's/^/    /'
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

validate_boolean() {
    local name="$1"
    local value="$2"

    case "${value}" in
        true|false)
            ;;
        *)
            printf 'ERROR: %s must be true or false. Received: %s\n' \
                "${name}" "${value}" >&2
            exit 2
            ;;
    esac
}

duration_seconds() {
    local end_epoch

    end_epoch="$(date +%s)"
    printf '%s' "$((end_epoch - START_EPOCH))"
}

########################################
# Resource Cleanup Helpers
########################################

wait_for_resource_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-}"
    local timeout_seconds="${4:-60}"
    local elapsed=0

    while (( elapsed < timeout_seconds )); do
        if [[ -n "${namespace}" ]]; then
            if ! kubectl get "${resource_type}" "${resource_name}" \
                --namespace "${namespace}" \
                >/dev/null 2>&1; then

                return 0
            fi
        else
            if ! kubectl get "${resource_type}" "${resource_name}" \
                >/dev/null 2>&1; then

                return 0
            fi
        fi

        sleep 1
        elapsed=$((elapsed + 1))
    done

    return 1
}

delete_dns_test_pod() {
    if [[ "${DNS_TEST_POD_CREATED}" != "true" ]]; then
        return 0
    fi

    kubectl delete pod "${DNS_TEST_POD}" \
        --namespace default \
        --ignore-not-found=true \
        --wait=false \
        >/dev/null 2>&1 || true

    if wait_for_resource_deletion \
        pod \
        "${DNS_TEST_POD}" \
        default \
        "${RESOURCE_DELETE_TIMEOUT_SECONDS}"; then

        info "DNS test pod cleanup completed."
    else
        warn "DNS test pod remains in Terminating state."
    fi

    DNS_TEST_POD_CREATED="false"
}

delete_smoke_namespace() {
    if [[ "${SMOKE_NAMESPACE_CREATED}" != "true" ]]; then
        return 0
    fi

    kubectl delete namespace "${SMOKE_NAMESPACE}" \
        --ignore-not-found=true \
        --wait=false \
        >/dev/null 2>&1 || true

    if wait_for_resource_deletion \
        namespace \
        "${SMOKE_NAMESPACE}" \
        "" \
        "${RESOURCE_DELETE_TIMEOUT_SECONDS}"; then

        info "Smoke-test namespace cleanup completed."
    else
        warn "Smoke-test namespace remains in Terminating state."
    fi

    SMOKE_NAMESPACE_CREATED="false"
}

cleanup() {
    local exit_code=$?

    if [[ "${CLEANUP_STARTED}" == "true" ]]; then
        return
    fi

    CLEANUP_STARTED="true"

    if command_exists kubectl &&
       kubectl cluster-info >/dev/null 2>&1; then

        if [[ "${DNS_TEST_POD_CREATED}" == "true" ]]; then
            kubectl delete pod "${DNS_TEST_POD}" \
                --namespace default \
                --ignore-not-found=true \
                --wait=false \
                >/dev/null 2>&1 || true
        fi

        if [[ "${SMOKE_NAMESPACE_CREATED}" == "true" ]]; then
            kubectl delete namespace "${SMOKE_NAMESPACE}" \
                --ignore-not-found=true \
                --wait=false \
                >/dev/null 2>&1 || true
        fi
    fi

    rm -rf "${TEMP_DIR}"

    return "${exit_code}"
}

on_error() {
    local exit_code=$?
    local line_number="${BASH_LINENO-unknown}"
    local command_name="${BASH_COMMAND:-unknown}"

    printf '\nUNEXPECTED ERROR: command failed at line %s\n' \
        "${line_number}" >&2
    printf 'Command: %s\n' "${command_name}" >&2
    printf 'Exit code: %s\n' "${exit_code}" >&2

    exit "${exit_code}"
}

on_signal() {
    printf '\nAudit interrupted. Cleaning up temporary resources...\n' >&2
    exit 130
}

trap cleanup EXIT
trap on_error ERR
trap on_signal INT TERM HUP

########################################
# Configuration Validation
########################################

validate_boolean "RUN_SMOKE_TESTS" "${RUN_SMOKE_TESTS}"
validate_boolean "CHECK_LOCAL_TIME_SYNC" "${CHECK_LOCAL_TIME_SYNC}"
validate_boolean "CHECK_LOCAL_CRI" "${CHECK_LOCAL_CRI}"
validate_boolean \
    "METRICS_SERVER_MISSING_IS_WARNING" \
    "${METRICS_SERVER_MISSING_IS_WARNING}"

########################################
# Start
########################################

print_header "Kubernetes Cluster Health Audit"

echo "Start Time      : ${START_TIME}"
echo "User            : $(whoami)"
echo "Audit Host      : $(hostname)"
echo "Audit Run ID    : ${RUN_SUFFIX}"
echo "Event Lookback  : ${EVENT_LOOKBACK_MINUTES} minutes"
echo "Smoke Tests     : ${RUN_SMOKE_TESTS}"

###############################################################################
# 1. Required Commands and API Connectivity
###############################################################################

print_section "1/20" "Checking prerequisites and Kubernetes API connectivity"

MISSING_COMMANDS=()

for required_command in kubectl jq date awk grep sed sort paste; do
    if ! command_exists "${required_command}"; then
        MISSING_COMMANDS+=("${required_command}")
    fi
done

if [[ "${#MISSING_COMMANDS[@]}" -gt 0 ]]; then
    fail "Required commands are missing: ${MISSING_COMMANDS[*]}"
    exit 1
fi

pass "Required local commands are available."

if kubectl cluster-info >/dev/null 2>&1; then
    pass "kubectl can communicate with the cluster."
else
    fail "kubectl cannot communicate with the cluster."
    exit 1
fi

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"

if [[ -n "${CURRENT_CONTEXT}" ]]; then
    info "Current context: ${CURRENT_CONTEXT}"
fi

info "Client and server versions:"
kubectl version 2>/dev/null | indent_output || true

###############################################################################
# 2. API Server Health
###############################################################################

print_section "2/20" "Checking API server livez and readyz"

if kubectl get --raw="/livez" >/dev/null 2>&1; then
    pass "API server livez endpoint returned successfully."
else
    fail "API server livez endpoint failed."

    kubectl get --raw="/livez?verbose" 2>/dev/null |
        indent_output || true
fi

if kubectl get --raw="/readyz" >/dev/null 2>&1; then
    pass "API server readyz endpoint returned successfully."
else
    fail "API server readyz endpoint failed."

    kubectl get --raw="/readyz?verbose" 2>/dev/null |
        indent_output || true
fi

###############################################################################
# 3. Collect Cluster Data
###############################################################################

print_section "3/20" "Collecting Kubernetes API data"

if kubectl get nodes -o json > "${NODE_JSON}" &&
   kubectl get pods -A -o json > "${POD_JSON}" &&
   kubectl get services -A -o json > "${SERVICE_JSON}" &&
   kubectl get events -A -o json > "${EVENT_JSON}" &&
   kubectl get pvc -A -o json > "${PVC_JSON}"; then

    pass "Core cluster data was collected successfully."
else
    fail "Failed to collect one or more Kubernetes resources."
    exit 1
fi

# Directly retrieve EndpointSlices instead of parsing kubectl api-resources.
if kubectl get endpointslices.discovery.k8s.io \
    --all-namespaces \
    -o json \
    > "${ENDPOINTSLICE_JSON}" 2>/dev/null; then

    ENDPOINTSLICE_AVAILABLE="true"
    pass "EndpointSlice data was collected successfully."
else
    ENDPOINTSLICE_AVAILABLE="false"
    warn "EndpointSlices could not be retrieved from discovery.k8s.io/v1."
    printf '{"items":[]}\n' > "${ENDPOINTSLICE_JSON}"
fi

###############################################################################
# 4. Node Readiness
###############################################################################

print_section "4/20" "Checking node Ready conditions"

NODE_COUNT="$(jq '.items | length' "${NODE_JSON}")"
info "Total nodes detected: ${NODE_COUNT}"

if [[ "${NODE_COUNT}" -eq 0 ]]; then
    fail "No Kubernetes nodes were found."
else
    NOT_READY_NODES="$(
        jq -r '
            .items[]
            | . as $node
            | (
                [
                    $node.status.conditions[]?
                    | select(.type == "Ready")
                ][0].status // "Unknown"
              ) as $ready
            | select($ready != "True")
            | "\($node.metadata.name) Ready=\($ready)"
        ' "${NODE_JSON}"
    )"

    if [[ -z "${NOT_READY_NODES}" ]]; then
        pass "All ${NODE_COUNT} nodes report Ready=True."
    else
        fail "One or more nodes are not Ready:"
        printf '%s\n' "${NOT_READY_NODES}" | indent_output
    fi
fi

echo
kubectl get nodes -o wide | indent_output

###############################################################################
# 5. Node Pressure, Network and Taints
###############################################################################

print_section "5/20" "Checking node pressure, network conditions and taints"

NODE_CONDITION_ISSUES="$(
    jq -r '
        .items[]
        | .metadata.name as $node
        | .status.conditions[]?
        | select(
            (
                .type == "MemoryPressure"
                or .type == "DiskPressure"
                or .type == "PIDPressure"
                or .type == "NetworkUnavailable"
            )
            and .status == "True"
        )
        | "\($node) \(.type)=\(.status) reason=\(.reason // "unknown") message=\(.message // "")"
    ' "${NODE_JSON}"
)"

if [[ -z "${NODE_CONDITION_ISSUES}" ]]; then
    pass "No node pressure or NetworkUnavailable conditions are active."
else
    fail "Node pressure or network conditions were detected:"
    printf '%s\n' "${NODE_CONDITION_ISSUES}" | indent_output
fi

UNEXPECTED_TAINTS="$(
    jq -r '
        .items[]
        | .metadata.name as $node
        | (.spec.taints // [])[]
        | select(
            .effect == "NoSchedule"
            or .effect == "NoExecute"
        )
        | select(
            .key != "node-role.kubernetes.io/control-plane"
            and .key != "node-role.kubernetes.io/master"
        )
        | "\($node) \(.key)=\(.value // ""):\(.effect)"
    ' "${NODE_JSON}"
)"

if [[ -z "${UNEXPECTED_TAINTS}" ]]; then
    pass "No unexpected NoSchedule or NoExecute node taints were found."
else
    warn "Scheduling-impacting node taints were found:"
    printf '%s\n' "${UNEXPECTED_TAINTS}" | indent_output
fi

###############################################################################
# 6. Pod Phase and Readiness Health
###############################################################################

print_section "6/20" "Checking pod phases and readiness using JSON data"

TERMINAL_OR_UNHEALTHY_PODS="$(
    jq -r '
        .items[]
        | select(.metadata.deletionTimestamp == null)
        | . as $pod
        | ($pod.status.phase // "Unknown") as $phase
        | (
            [
                $pod.status.conditions[]?
                | select(.type == "Ready")
            ][0].status // "Unknown"
          ) as $ready
        | select(
            $phase == "Failed"
            or $phase == "Unknown"
            or (
                $phase == "Running"
                and $ready != "True"
            )
        )
        | "\($pod.metadata.namespace)/\($pod.metadata.name) phase=\($phase) ready=\($ready) node=\($pod.spec.nodeName // "unscheduled")"
    ' "${POD_JSON}"
)"

PENDING_PODS="$(
    jq -r '
        .items[]
        | select(.metadata.deletionTimestamp == null)
        | select(.status.phase == "Pending")
        | "\(.metadata.namespace)/\(.metadata.name) node=\(.spec.nodeName // "unscheduled")"
    ' "${POD_JSON}"
)"

if [[ -z "${TERMINAL_OR_UNHEALTHY_PODS}" ]]; then
    pass "No failed, unknown or unready Running pods were found."
else
    fail "Unhealthy pods were detected:"
    printf '%s\n' "${TERMINAL_OR_UNHEALTHY_PODS}" | indent_output
fi

if [[ -z "${PENDING_PODS}" ]]; then
    pass "No non-terminating Pending pods were found."
else
    warn "Pending pods were detected:"
    printf '%s\n' "${PENDING_PODS}" | indent_output
fi

###############################################################################
# 7. Container and Init-Container State Health
###############################################################################

print_section "7/20" "Checking container and init-container states"

CONTAINER_STATE_ISSUES="$(
    jq -r '
        .items[]
        | select(.metadata.deletionTimestamp == null)
        | . as $pod
        | (
            ($pod.status.initContainerStatuses // [])
            + ($pod.status.containerStatuses // [])
            + ($pod.status.ephemeralContainerStatuses // [])
          )[]
        | select(
            .state.waiting.reason? as $reason
            | $reason != null
            and $reason != "ContainerCreating"
            and $reason != "PodInitializing"
        )
        | "\($pod.metadata.namespace)/\($pod.metadata.name) container=\(.name) waiting=\(.state.waiting.reason) message=\(.state.waiting.message // "")"
    ' "${POD_JSON}"
)"

TERMINATED_CONTAINER_ISSUES="$(
    jq -r '
        .items[]
        | select(.metadata.deletionTimestamp == null)
        | . as $pod
        | (
            ($pod.status.initContainerStatuses // [])
            + ($pod.status.containerStatuses // [])
          )[]
        | select(
            .state.terminated.exitCode? != null
            and .state.terminated.exitCode != 0
            and .state.terminated.reason != "Completed"
        )
        | "\($pod.metadata.namespace)/\($pod.metadata.name) container=\(.name) exitCode=\(.state.terminated.exitCode) reason=\(.state.terminated.reason // "unknown")"
    ' "${POD_JSON}"
)"

if [[ -z "${CONTAINER_STATE_ISSUES}" &&
      -z "${TERMINATED_CONTAINER_ISSUES}" ]]; then

    pass "No problematic container or init-container states were found."
else
    fail "Problematic container states were detected."

    if [[ -n "${CONTAINER_STATE_ISSUES}" ]]; then
        printf '%s\n' "${CONTAINER_STATE_ISSUES}" | indent_output
    fi

    if [[ -n "${TERMINATED_CONTAINER_ISSUES}" ]]; then
        printf '%s\n' "${TERMINATED_CONTAINER_ISSUES}" | indent_output
    fi
fi

###############################################################################
# 8. Pod Restart Counts
###############################################################################

print_section "8/20" "Checking pod restart counts"

RESTART_REPORT="$(
    jq -r '
        .items[]
        | select(.metadata.deletionTimestamp == null)
        | . as $pod
        | (
            (
                ($pod.status.initContainerStatuses // [])
                + ($pod.status.containerStatuses // [])
                + ($pod.status.ephemeralContainerStatuses // [])
            )
            | map(.restartCount // 0)
            | add // 0
          ) as $total
        | select($total > 0)
        | "\($pod.metadata.namespace)\t\($pod.metadata.name)\t\($total)"
    ' "${POD_JSON}"
)"

RESTART_FAIL_REPORT=""
RESTART_WARN_REPORT=""

while IFS=$'\t' read -r namespace pod total_restarts; do
    [[ -z "${namespace:-}" ]] && continue

    if (( total_restarts >= RESTART_FAIL_THRESHOLD )); then
        RESTART_FAIL_REPORT+="${namespace}/${pod} restarts=${total_restarts}"$'\n'
    elif (( total_restarts >= RESTART_WARN_THRESHOLD )); then
        RESTART_WARN_REPORT+="${namespace}/${pod} restarts=${total_restarts}"$'\n'
    fi
done <<< "${RESTART_REPORT}"

if [[ -n "${RESTART_FAIL_REPORT}" ]]; then
    fail "Pods exceeding the restart failure threshold were found:"
    printf '%s' "${RESTART_FAIL_REPORT}" | indent_output
elif [[ -n "${RESTART_WARN_REPORT}" ]]; then
    warn "Pods exceeding the restart warning threshold were found:"
    printf '%s' "${RESTART_WARN_REPORT}" | indent_output
else
    pass "Pod restart counts are below configured thresholds."
fi

###############################################################################
# 9. CoreDNS Health
###############################################################################

print_section "9/20" "Checking CoreDNS pods, Service and EndpointSlices"

COREDNS_PODS="$(
    jq -r '
        .items[]
        | select(.metadata.namespace == "kube-system")
        | select(.metadata.labels["k8s-app"] == "kube-dns")
        | . as $pod
        | (
            [
                $pod.status.conditions[]?
                | select(.type == "Ready")
            ][0].status // "Unknown"
          ) as $ready
        | "\($pod.metadata.name)\t\($pod.status.phase // "Unknown")\t\($ready)"
    ' "${POD_JSON}"
)"

if [[ -z "${COREDNS_PODS}" ]]; then
    fail "No CoreDNS pods were found using label k8s-app=kube-dns."
else
    COREDNS_BAD="$(
        printf '%s\n' "${COREDNS_PODS}" |
        awk -F '\t' '$2 != "Running" || $3 != "True"'
    )"

    if [[ -z "${COREDNS_BAD}" ]]; then
        pass "All discovered CoreDNS pods are Running and Ready."
    else
        fail "One or more CoreDNS pods are unhealthy:"
        printf '%s\n' "${COREDNS_BAD}" | indent_output
    fi
fi

if kubectl get service kube-dns \
    --namespace kube-system >/dev/null 2>&1; then

    pass "kube-dns Service exists."
else
    fail "kube-dns Service is missing."
fi

if [[ "${ENDPOINTSLICE_AVAILABLE}" == "true" ]]; then
    COREDNS_SLICE_ADDRESSES="$(
        jq -r '
            .items[]
            | select(.metadata.namespace == "kube-system")
            | select(.metadata.labels["kubernetes.io/service-name"] == "kube-dns")
            | .endpoints[]?
            | select(
                (.conditions.ready // true) == true
                and (.conditions.terminating // false) == false
            )
            | .addresses[]?
        ' "${ENDPOINTSLICE_JSON}" |
        sort -u |
        paste -sd ' ' -
    )"

    if [[ -n "${COREDNS_SLICE_ADDRESSES}" ]]; then
        pass "kube-dns has ready EndpointSlice addresses: ${COREDNS_SLICE_ADDRESSES}"
    else
        fail "kube-dns has no ready EndpointSlice addresses."
    fi
else
    skip "CoreDNS EndpointSlice validation is unavailable."
fi

###############################################################################
# 10. DNS Resolution Smoke Test
###############################################################################

print_section "10/20" "Testing DNS resolution from inside the cluster"

if [[ "${RUN_SMOKE_TESTS}" != "true" ]]; then
    skip "DNS smoke test is disabled."
else
    KUBERNETES_SERVICE_IP="$(
        kubectl get service kubernetes \
            --namespace default \
            -o jsonpath='{.spec.clusterIP}' \
            2>/dev/null || true
    )"

    if [[ -n "${KUBERNETES_SERVICE_IP}" ]]; then
        info "Kubernetes Service IP: ${KUBERNETES_SERVICE_IP}"
    else
        warn "Unable to retrieve the Kubernetes Service ClusterIP."
    fi

    if kubectl run "${DNS_TEST_POD}" \
        --namespace default \
        --image="${DNS_TEST_IMAGE}" \
        --restart=Never \
        --labels="cluster-health-audit=${RUN_SUFFIX}" \
        --command -- sleep 3600 \
        >/dev/null 2>&1; then

        DNS_TEST_POD_CREATED="true"
        pass "Created DNS test pod ${DNS_TEST_POD}."
    else
        fail "Failed to create DNS test pod ${DNS_TEST_POD}."
    fi

    if [[ "${DNS_TEST_POD_CREATED}" == "true" ]]; then
        if kubectl wait \
            --namespace default \
            --for=condition=Ready \
            "pod/${DNS_TEST_POD}" \
            --timeout="${DNS_TIMEOUT_SECONDS}s" \
            >/dev/null 2>&1; then

            pass "DNS test pod became Ready."
        else
            fail "DNS test pod did not become Ready."

            kubectl describe pod "${DNS_TEST_POD}" \
                --namespace default 2>/dev/null |
                indent_output || true
        fi
    fi

    DNS_TEST_READY="false"

    if [[ "${DNS_TEST_POD_CREATED}" == "true" ]]; then
        DNS_READY_STATUS="$(
            kubectl get pod "${DNS_TEST_POD}" \
                --namespace default \
                -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
                2>/dev/null || true
        )"

        if [[ "${DNS_READY_STATUS}" == "True" ]]; then
            DNS_TEST_READY="true"
        fi
    fi

    if [[ "${DNS_TEST_READY}" == "true" ]]; then
        info "DNS test pod resolv.conf:"

        kubectl exec \
            --namespace default \
            "${DNS_TEST_POD}" \
            -- cat /etc/resolv.conf 2>/dev/null |
            indent_output || true

        DNS_KUBERNETES_OUTPUT="$(
            kubectl exec \
                --namespace default \
                "${DNS_TEST_POD}" \
                -- nslookup kubernetes.default.svc.cluster.local \
                2>&1 || true
        )"

        if [[ -n "${KUBERNETES_SERVICE_IP}" ]] &&
           printf '%s\n' "${DNS_KUBERNETES_OUTPUT}" |
           grep -Fq "${KUBERNETES_SERVICE_IP}"; then

            pass "DNS resolves kubernetes.default.svc.cluster.local to ${KUBERNETES_SERVICE_IP}."
        else
            fail "DNS did not resolve kubernetes.default.svc.cluster.local to the configured Kubernetes Service IP."

            printf '%s\n' "${DNS_KUBERNETES_OUTPUT}" |
                indent_output
        fi

        KUBE_DNS_SERVICE_IP="$(
            kubectl get service kube-dns \
                --namespace kube-system \
                -o jsonpath='{.spec.clusterIP}' \
                2>/dev/null || true
        )"

        DNS_COREDNS_OUTPUT="$(
            kubectl exec \
                --namespace default \
                "${DNS_TEST_POD}" \
                -- nslookup kube-dns.kube-system.svc.cluster.local \
                2>&1 || true
        )"

        if [[ -n "${KUBE_DNS_SERVICE_IP}" ]] &&
           printf '%s\n' "${DNS_COREDNS_OUTPUT}" |
           grep -Fq "${KUBE_DNS_SERVICE_IP}"; then

            pass "DNS resolves kube-dns.kube-system.svc.cluster.local to ${KUBE_DNS_SERVICE_IP}."
        else
            fail "DNS did not resolve kube-dns.kube-system.svc.cluster.local to the configured kube-dns Service IP."

            printf '%s\n' "${DNS_COREDNS_OUTPUT}" |
                indent_output
        fi
    fi

    delete_dns_test_pod
fi

###############################################################################
# 11. Pod-to-Service Networking Smoke Test
###############################################################################

print_section "11/20" "Testing CNI and Pod-to-Service networking"

if [[ "${RUN_SMOKE_TESTS}" != "true" ]]; then
    skip "Pod-to-Service networking smoke test is disabled."
else
    if kubectl create namespace "${SMOKE_NAMESPACE}" >/dev/null 2>&1; then
        SMOKE_NAMESPACE_CREATED="true"
        pass "Created smoke-test namespace ${SMOKE_NAMESPACE}."
    else
        fail "Failed to create smoke-test namespace ${SMOKE_NAMESPACE}."
    fi

    if [[ "${SMOKE_NAMESPACE_CREATED}" == "true" ]]; then
        if kubectl run "${NGINX_TEST_POD}" \
            --namespace "${SMOKE_NAMESPACE}" \
            --image="${NGINX_TEST_IMAGE}" \
            --restart=Never \
            --labels="app=${NGINX_TEST_POD},cluster-health-audit=${RUN_SUFFIX}" \
            >/dev/null 2>&1; then

            pass "Created nginx smoke-test pod."
        else
            fail "Failed to create nginx smoke-test pod."
        fi

        if kubectl wait \
            --namespace "${SMOKE_NAMESPACE}" \
            --for=condition=Ready \
            "pod/${NGINX_TEST_POD}" \
            --timeout="${POD_TIMEOUT_SECONDS}s" \
            >/dev/null 2>&1; then

            pass "nginx smoke-test pod became Ready."
        else
            fail "nginx smoke-test pod did not become Ready."

            kubectl describe pod "${NGINX_TEST_POD}" \
                --namespace "${SMOKE_NAMESPACE}" 2>/dev/null |
                indent_output || true
        fi

        if kubectl expose pod "${NGINX_TEST_POD}" \
            --namespace "${SMOKE_NAMESPACE}" \
            --name="${NGINX_TEST_SERVICE}" \
            --port=80 \
            --target-port=80 \
            >/dev/null 2>&1; then

            pass "Created nginx smoke-test Service."
        else
            fail "Failed to create nginx smoke-test Service."
        fi

        SMOKE_ENDPOINT_READY="false"
        SMOKE_ENDPOINTS=""

        if [[ "${ENDPOINTSLICE_AVAILABLE}" == "true" ]]; then
            for ((attempt = 1; attempt <= 30; attempt++)); do
                SMOKE_ENDPOINTS="$(
                    kubectl get endpointslices.discovery.k8s.io \
                        --namespace "${SMOKE_NAMESPACE}" \
                        --selector \
                        "kubernetes.io/service-name=${NGINX_TEST_SERVICE}" \
                        -o json 2>/dev/null |
                    jq -r '
                        .items[].endpoints[]?
                        | select(
                            (.conditions.ready // true) == true
                            and (.conditions.terminating // false) == false
                        )
                        | .addresses[]?
                    ' 2>/dev/null |
                    sort -u |
                    paste -sd ' ' -
                )"

                if [[ -n "${SMOKE_ENDPOINTS}" ]]; then
                    SMOKE_ENDPOINT_READY="true"
                    break
                fi

                sleep 1
            done
        fi

        if [[ "${SMOKE_ENDPOINT_READY}" == "true" ]]; then
            pass "Smoke-test Service has ready EndpointSlice addresses: ${SMOKE_ENDPOINTS}"
        elif [[ "${ENDPOINTSLICE_AVAILABLE}" == "true" ]]; then
            fail "Smoke-test Service has no ready EndpointSlice addresses."
        else
            skip "Smoke-test EndpointSlice validation is unavailable."
        fi

        SERVICE_URL="http://${NGINX_TEST_SERVICE}.${SMOKE_NAMESPACE}.svc.cluster.local"

        if kubectl run "${CURL_TEST_POD}" \
            --namespace "${SMOKE_NAMESPACE}" \
            --image="${CURL_TEST_IMAGE}" \
            --restart=Never \
            --labels="cluster-health-audit=${RUN_SUFFIX}" \
            --command -- \
            curl \
                --fail \
                --silent \
                --show-error \
                --max-time 15 \
                "${SERVICE_URL}" \
            >/dev/null 2>&1; then

            if kubectl wait \
                --namespace "${SMOKE_NAMESPACE}" \
                --for=jsonpath='{.status.phase}'=Succeeded \
                "pod/${CURL_TEST_POD}" \
                --timeout="${CONNECTIVITY_TIMEOUT_SECONDS}s" \
                >/dev/null 2>&1; then

                pass "Pod-to-Service networking works through the Service FQDN."
            else
                fail "Service connectivity test pod did not complete successfully."

                kubectl logs "${CURL_TEST_POD}" \
                    --namespace "${SMOKE_NAMESPACE}" 2>/dev/null |
                    indent_output || true

                kubectl describe pod "${CURL_TEST_POD}" \
                    --namespace "${SMOKE_NAMESPACE}" 2>/dev/null |
                    indent_output || true
            fi
        else
            fail "Failed to create the Service connectivity test pod."
        fi
    fi

    delete_smoke_namespace
fi

###############################################################################
# 12. Service and EndpointSlice Health
###############################################################################

print_section "12/20" "Checking selector-based Services and EndpointSlices"

if [[ "${ENDPOINTSLICE_AVAILABLE}" != "true" ]]; then
    skip "Service EndpointSlice audit is unavailable."
else
    SERVICES_WITHOUT_READY_ENDPOINTS="$(
        jq -r '
            .items[]
            | select(.spec.type != "ExternalName")
            | select((.spec.selector // {}) | length > 0)
            | [
                .metadata.namespace,
                .metadata.name,
                (.spec.publishNotReadyAddresses // false)
              ]
            | @tsv
        ' "${SERVICE_JSON}" |
        while IFS=$'\t' read -r namespace service publish_not_ready; do
            [[ -z "${namespace:-}" ]] && continue

            READY_COUNT="$(
                jq \
                    --arg namespace "${namespace}" \
                    --arg service "${service}" \
                    --arg publish_not_ready "${publish_not_ready}" '
                    [
                        .items[]
                        | select(.metadata.namespace == $namespace)
                        | select(
                            .metadata.labels["kubernetes.io/service-name"]
                            == $service
                        )
                        | .endpoints[]?
                        | select(
                            (
                                (.conditions.ready // true) == true
                                or $publish_not_ready == "true"
                            )
                            and
                            (.conditions.terminating // false) == false
                        )
                        | .addresses[]?
                    ]
                    | length
                ' "${ENDPOINTSLICE_JSON}"
            )"

            if [[ "${READY_COUNT}" -eq 0 ]]; then
                printf '%s/%s\n' "${namespace}" "${service}"
            fi
        done
    )"

    if [[ -z "${SERVICES_WITHOUT_READY_ENDPOINTS}" ]]; then
        pass "All selector-based Services have ready EndpointSlice backends."
    else
        warn "Selector-based Services without ready EndpointSlice backends:"
        printf '%s\n' "${SERVICES_WITHOUT_READY_ENDPOINTS}" | indent_output
    fi
fi

###############################################################################
# 13. Persistent Storage Health
###############################################################################

print_section "13/20" "Checking PersistentVolumeClaims and StorageClasses"

PVC_COUNT="$(jq '.items | length' "${PVC_JSON}")"

if [[ "${PVC_COUNT}" -eq 0 ]]; then
    info "No PersistentVolumeClaims exist."
    skip "PVC binding check is not applicable."
else
    BAD_PVCS="$(
        jq -r '
            .items[]
            | select(.metadata.deletionTimestamp == null)
            | select(.status.phase != "Bound")
            | "\(.metadata.namespace)/\(.metadata.name) phase=\(.status.phase // "Unknown") storageClass=\(.spec.storageClassName // "none")"
        ' "${PVC_JSON}"
    )"

    if [[ -z "${BAD_PVCS}" ]]; then
        pass "All ${PVC_COUNT} PersistentVolumeClaims are Bound."
    else
        fail "PersistentVolumeClaims not in Bound state:"
        printf '%s\n' "${BAD_PVCS}" | indent_output
    fi
fi

STORAGE_CLASSES="$(
    kubectl get storageclasses.storage.k8s.io -o json 2>/dev/null || true
)"

if [[ -z "${STORAGE_CLASSES}" ]]; then
    warn "StorageClass information could not be retrieved."
else
    STORAGE_CLASS_COUNT="$(
        jq '.items | length' <<< "${STORAGE_CLASSES}"
    )"

    DEFAULT_STORAGE_CLASS_COUNT="$(
        jq '
            [
                .items[]
                | select(
                    .metadata.annotations[
                        "storageclass.kubernetes.io/is-default-class"
                    ] == "true"
                    or
                    .metadata.annotations[
                        "storageclass.beta.kubernetes.io/is-default-class"
                    ] == "true"
                )
            ]
            | length
        ' <<< "${STORAGE_CLASSES}"
    )"

    if [[ "${STORAGE_CLASS_COUNT}" -eq 0 ]]; then
        info "No StorageClasses are installed."
        skip "StorageClass default check is not applicable."
    elif [[ "${DEFAULT_STORAGE_CLASS_COUNT}" -eq 1 ]]; then
        pass "Exactly one default StorageClass is configured."
    elif [[ "${DEFAULT_STORAGE_CLASS_COUNT}" -eq 0 ]]; then
        warn "StorageClasses exist, but none is configured as default."
    else
        warn "Multiple default StorageClasses are configured."
    fi
fi

###############################################################################
# 14. Recent Warning Events
###############################################################################

print_section "14/20" "Checking recent Warning events"

EVENT_CUTOFF_EPOCH="$(
    date -u -d "${EVENT_LOOKBACK_MINUTES} minutes ago" +%s
)"

RECENT_WARNING_EVENTS="$(
    jq -r \
        --argjson cutoff "${EVENT_CUTOFF_EPOCH}" '
        def event_timestamp:
            (
                .eventTime
                // .series.lastObservedTime
                // .deprecatedLastTimestamp
                // .lastTimestamp
                // .metadata.creationTimestamp
                // ""
            );

        def normalized_timestamp:
            event_timestamp
            | sub("\\.[0-9]+Z$"; "Z");

        .items[]
        | select(.type == "Warning")
        | (normalized_timestamp) as $timestamp
        | select($timestamp != "")
        | (
            try (
                $timestamp
                | fromdateiso8601
            ) catch 0
          ) as $epoch
        | select($epoch >= $cutoff)
        | [
            $epoch,
            $timestamp,
            (.metadata.namespace // "default"),
            (.reason // "Unknown"),
            (
                (
                    .regarding.kind
                    // .involvedObject.kind
                    // "Object"
                )
                + "/"
                + (
                    .regarding.name
                    // .involvedObject.name
                    // "unknown"
                )
            ),
            (.note // .message // ""),
            (
                .series.count
                // .deprecatedCount
                // .count
                // 1
            )
          ]
        | @tsv
    ' "${EVENT_JSON}" |
    sort -n -k1,1 |
    tail -n "${MAX_WARNING_EVENTS}"
)"

if [[ -z "${RECENT_WARNING_EVENTS}" ]]; then
    pass "No Warning events occurred during the last ${EVENT_LOOKBACK_MINUTES} minutes."
else
    warn "Recent Warning events occurred during the last ${EVENT_LOOKBACK_MINUTES} minutes:"

    while IFS=$'\t' read -r \
        event_epoch \
        event_time \
        namespace \
        reason \
        object \
        message \
        count; do

        printf '    [%s] namespace=%s reason=%s object=%s count=%s\n' \
            "${event_time}" \
            "${namespace}" \
            "${reason}" \
            "${object}" \
            "${count}"

        printf '      %s\n' "${message}"
    done <<< "${RECENT_WARNING_EVENTS}"
fi

###############################################################################
# 15. Calico and Tigera Operator Health
###############################################################################

print_section "15/20" "Checking Calico and Tigera Operator health"

if kubectl get tigerastatus -o json >/dev/null 2>&1; then
    CALICO_PRESENT="true"

    TIGERA_JSON="$(
        kubectl get tigerastatus -o json 2>/dev/null || true
    )"

    TIGERA_BAD="$(
        jq -r '
            .items[]
            | . as $item
            | (
                [
                    $item.status.conditions[]?
                    | select(.type == "Available")
                ][0].status // "Unknown"
              ) as $available
            | (
                [
                    $item.status.conditions[]?
                    | select(.type == "Degraded")
                ][0].status // "Unknown"
              ) as $degraded
            | (
                [
                    $item.status.conditions[]?
                    | select(.type == "Progressing")
                ][0].status // "Unknown"
              ) as $progressing
            | select(
                $available != "True"
                or $degraded == "True"
            )
            | "\($item.metadata.name) available=\($available) progressing=\($progressing) degraded=\($degraded)"
        ' <<< "${TIGERA_JSON}"
    )"

    if [[ -z "${TIGERA_BAD}" ]]; then
        pass "All Tigera components are Available and not Degraded."
    else
        fail "Unhealthy Tigera component status was detected:"
        printf '%s\n' "${TIGERA_BAD}" | indent_output
    fi

    info "Tigera component status:"
    kubectl get tigerastatus 2>/dev/null |
        indent_output || true
else
    skip "TigeraStatus resources were not detected."
fi

CALICO_NODE_JSON="$(
    jq '
        {
            items: [
                .items[]
                | select(
                    .metadata.namespace == "calico-system"
                    and .metadata.labels["k8s-app"] == "calico-node"
                )
            ]
        }
    ' "${POD_JSON}"
)"

CALICO_NODE_COUNT="$(
    jq '.items | length' <<< "${CALICO_NODE_JSON}"
)"

if [[ "${CALICO_NODE_COUNT}" -gt 0 ]]; then
    CALICO_PRESENT="true"

    CALICO_NODE_BAD="$(
        jq -r '
            .items[]
            | . as $pod
            | (
                [
                    $pod.status.conditions[]?
                    | select(.type == "Ready")
                ][0].status // "Unknown"
              ) as $ready
            | select(
                $pod.status.phase != "Running"
                or $ready != "True"
            )
            | "\($pod.metadata.name) node=\($pod.spec.nodeName // "unknown") phase=\($pod.status.phase // "Unknown") ready=\($ready)"
        ' <<< "${CALICO_NODE_JSON}"
    )"

    if [[ -z "${CALICO_NODE_BAD}" ]]; then
        pass "All ${CALICO_NODE_COUNT} calico-node pods are Running and Ready."
    else
        fail "Unhealthy calico-node pods were detected:"
        printf '%s\n' "${CALICO_NODE_BAD}" | indent_output
    fi
elif [[ "${CALICO_PRESENT}" == "true" ]]; then
    fail "Calico appears installed, but no calico-node pods were found."
else
    skip "Calico was not detected."
fi

###############################################################################
# 16. Calico eBPF Validation
###############################################################################

print_section "16/20" "Checking Calico eBPF configuration and runtime evidence"

if kubectl get installations.operator.tigera.io default \
    -o json >/dev/null 2>&1; then

    INSTALLATION_JSON="$(
        kubectl get installations.operator.tigera.io default -o json
    )"

    LINUX_DATAPLANE="$(
        jq -r '.spec.calicoNetwork.linuxDataplane // "NotSet"' \
            <<< "${INSTALLATION_JSON}"
    )"

    BPF_BOOTSTRAP="$(
        jq -r '.spec.calicoNetwork.bpfNetworkBootstrap // "NotSet"' \
            <<< "${INSTALLATION_JSON}"
    )"

    KUBEPROXY_MANAGEMENT="$(
        jq -r '.spec.calicoNetwork.kubeProxyManagement // "NotSet"' \
            <<< "${INSTALLATION_JSON}"
    )"

    info "linuxDataplane: ${LINUX_DATAPLANE}"
    info "bpfNetworkBootstrap: ${BPF_BOOTSTRAP}"
    info "kubeProxyManagement: ${KUBEPROXY_MANAGEMENT}"

    if [[ "${LINUX_DATAPLANE}" == "BPF" ]]; then
        CALICO_EBPF_CONFIGURED="true"
        pass "Calico Installation requests the BPF dataplane."
    else
        skip "Calico is not configured with linuxDataplane=BPF."
    fi

    if [[ "${CALICO_EBPF_CONFIGURED}" == "true" ]]; then
        if [[ "${BPF_BOOTSTRAP}" == "Enabled" ]]; then
            pass "Calico BPF network bootstrap is enabled."
        else
            warn "Calico eBPF is selected, but bpfNetworkBootstrap is ${BPF_BOOTSTRAP}."
        fi

        if [[ "${KUBEPROXY_MANAGEMENT}" == "Enabled" ]]; then
            pass "Calico kube-proxy management is enabled."
        else
            warn "Calico eBPF is selected, but kubeProxyManagement is ${KUBEPROXY_MANAGEMENT}."
        fi
    fi
else
    skip "Calico Operator Installation resource was not found."
fi

if [[ "${CALICO_EBPF_CONFIGURED}" == "true" &&
      "${CALICO_NODE_COUNT}" -gt 0 ]]; then

    BPF_INTERFACE_NODES="$(
        jq -r '
            .items[]
            | select(
                (
                    .metadata.annotations["projectcalico.org/Interfaces"]
                    // ""
                )
                | test("bpfin\\.cali|bpfout\\.cali")
            )
            | .metadata.name
        ' "${NODE_JSON}"
    )"

    if [[ -n "${BPF_INTERFACE_NODES}" ]]; then
        BPF_INTERFACE_NODE_COUNT="$(
            printf '%s\n' "${BPF_INTERFACE_NODES}" |
            grep -c . || true
        )"

        pass "Calico BPF interface annotations were found on ${BPF_INTERFACE_NODE_COUNT} node(s)."
    else
        info "BPF interface annotations were not found on Kubernetes Node objects."
        info "Some Calico versions may not publish these annotations consistently."
    fi

    BPF_LOG_CONFIRMED=0
    BPF_LOG_UNSUPPORTED=0
    BPF_RUNTIME_CHECKED=0

    while IFS=$'\t' read -r calico_namespace calico_pod calico_node; do
        [[ -z "${calico_pod:-}" ]] && continue

        BPF_RUNTIME_CHECKED=$((BPF_RUNTIME_CHECKED + 1))

        CALICO_LOG_SAMPLE="$(
            kubectl logs \
                --namespace "${calico_namespace}" \
                "${calico_pod}" \
                --container calico-node \
                --tail="${CALICO_LOG_TAIL_LINES}" \
                2>/dev/null || true
        )"

        if printf '%s\n' "${CALICO_LOG_SAMPLE}" |
           grep -qiE \
               'BPF enabled, starting BPF endpoint manager|BPF data plane|Dataplane mode.*BPF'; then

            BPF_LOG_CONFIRMED=$((BPF_LOG_CONFIRMED + 1))
        fi

        if printf '%s\n' "${CALICO_LOG_SAMPLE}" |
           grep -qi \
               'BPF data plane mode enabled but not supported by the kernel'; then

            BPF_LOG_UNSUPPORTED=$((BPF_LOG_UNSUPPORTED + 1))
            fail "Calico reported unsupported BPF mode on ${calico_node}/${calico_pod}."
        fi
    done < <(
        jq -r '
            .items[]
            | [
                .metadata.namespace,
                .metadata.name,
                (.spec.nodeName // "unknown")
              ]
            | @tsv
        ' <<< "${CALICO_NODE_JSON}"
    )

    if [[ "${BPF_LOG_UNSUPPORTED}" -eq 0 ]]; then
        pass "No Calico logs reported unsupported BPF kernel functionality."
    fi

    if [[ "${BPF_LOG_CONFIRMED}" -gt 0 ]]; then
        pass "Calico BPF runtime evidence was found in ${BPF_LOG_CONFIRMED}/${BPF_RUNTIME_CHECKED} sampled calico-node logs."
    else
        info "BPF startup text was not found in the current calico-node log tails."
        info "Startup messages may have rotated from the current logs."
    fi

    KUBEPROXY_POD_COUNT="$(
        jq '
            [
                .items[]
                | select(.metadata.namespace == "kube-system")
                | select(
                    .metadata.labels["k8s-app"] == "kube-proxy"
                    or .metadata.labels["component"] == "kube-proxy"
                    or (.metadata.name | startswith("kube-proxy-"))
                )
                | select(.metadata.deletionTimestamp == null)
            ]
            | length
        ' "${POD_JSON}"
    )"

    if [[ "${KUBEPROXY_MANAGEMENT}" == "Enabled" ]]; then
        if [[ "${KUBEPROXY_POD_COUNT}" -eq 0 ]]; then
            pass "No active kube-proxy pods remain under Calico-managed eBPF mode."
        else
            warn "${KUBEPROXY_POD_COUNT} kube-proxy pods still exist while Calico kubeProxyManagement is Enabled."
        fi
    fi
else
    skip "Calico eBPF runtime validation is not applicable."
fi

###############################################################################
# 17. Local Time Synchronization
###############################################################################

print_section "17/20" "Checking local time synchronization"

if [[ "${CHECK_LOCAL_TIME_SYNC}" != "true" ]]; then
    skip "Local time synchronization validation is disabled."
elif ! command_exists timedatectl; then
    warn "timedatectl is unavailable. Time synchronization was not checked."
else
    NTP_SYNCHRONIZED="$(
        timedatectl show \
            --property=NTPSynchronized \
            --value 2>/dev/null || true
    )"

    NTP_SERVICE="$(
        timedatectl show \
            --property=NTP \
            --value 2>/dev/null || true
    )"

    TIMEZONE="$(
        timedatectl show \
            --property=Timezone \
            --value 2>/dev/null || true
    )"

    info "Audit host time: $(date --iso-8601=seconds 2>/dev/null || date)"
    info "Timezone: ${TIMEZONE:-unknown}"
    info "NTP service enabled: ${NTP_SERVICE:-unknown}"
    info "Clock synchronized: ${NTP_SYNCHRONIZED:-unknown}"

    if [[ "${NTP_SYNCHRONIZED}" == "yes" ]]; then
        pass "The audit host system clock is synchronized."
    else
        warn "The audit host system clock is not confirmed as synchronized."
    fi

    if [[ "${NTP_SERVICE}" == "yes" ]]; then
        pass "An NTP synchronization service is active on the audit host."
    else
        warn "No active NTP synchronization service was confirmed."
    fi
fi

###############################################################################
# 18. Local Container Runtime
###############################################################################

print_section "18/20" "Checking local container runtime with crictl"

if [[ "${CHECK_LOCAL_CRI}" != "true" ]]; then
    skip "Local CRI validation is disabled."
elif ! command_exists crictl; then
    warn "crictl is not installed on the audit host."
else
    CRI_COMMAND=()

    if crictl info >/dev/null 2>&1; then
        CRI_COMMAND=(crictl)
        pass "crictl can communicate with the runtime as the current user."
    elif command_exists sudo &&
         sudo -n crictl info >/dev/null 2>&1; then

        CRI_COMMAND=(sudo -n crictl)
        pass "crictl can communicate with the runtime using noninteractive sudo."
    else
        fail "crictl cannot communicate with the local container runtime."
    fi

    if [[ "${#CRI_COMMAND[@]}" -gt 0 ]]; then
        info "Container runtime version:"

        "${CRI_COMMAND[@]}" version 2>/dev/null |
            indent_output || true
    fi
fi

###############################################################################
# 19. Metrics API
###############################################################################

print_section "19/20" "Checking Metrics Server and resource metrics"

if kubectl get apiservice v1beta1.metrics.k8s.io \
    >/dev/null 2>&1; then

    METRICS_API_AVAILABLE="$(
        kubectl get apiservice v1beta1.metrics.k8s.io \
            -o json |
        jq -r '
            [
                .status.conditions[]?
                | select(.type == "Available")
            ][0].status // "Unknown"
        '
    )"

    if [[ "${METRICS_API_AVAILABLE}" == "True" ]]; then
        pass "Metrics APIService reports Available=True."

        if kubectl top nodes >/dev/null 2>&1; then
            pass "kubectl top nodes returned resource metrics."

            kubectl top nodes |
                indent_output || true
        else
            warn "Metrics API is Available, but kubectl top nodes failed."
        fi

        if kubectl top pods -A >/dev/null 2>&1; then
            pass "kubectl top pods can retrieve workload metrics."
        else
            warn "Metrics API is Available, but kubectl top pods failed."
        fi
    else
        warn "Metrics APIService exists but Available=${METRICS_API_AVAILABLE}."

        kubectl get apiservice v1beta1.metrics.k8s.io -o wide |
            indent_output || true
    fi
else
    if [[ "${METRICS_SERVER_MISSING_IS_WARNING}" == "true" ]]; then
        warn "Metrics Server is not installed."
    else
        skip "Metrics Server is not installed."
    fi
fi

###############################################################################
# 20. Final Snapshot
###############################################################################

print_section "20/20" "Displaying final cluster snapshot"

# Safety cleanup before displaying the final snapshot.
delete_dns_test_pod
delete_smoke_namespace

info "Nodes:"
kubectl get nodes -o wide 2>/dev/null |
    indent_output || true

info "Active non-completed pods:"
kubectl get pods -A \
    --field-selector=status.phase!=Succeeded \
    -o wide 2>/dev/null |
    awk -v dns_pod="${DNS_TEST_POD}" \
        -v smoke_namespace="${SMOKE_NAMESPACE}" '
        NR == 1 {
            print
            next
        }

        $1 == smoke_namespace {
            next
        }

        $2 == dns_pod {
            next
        }

        {
            print
        }
    ' |
    indent_output || true

if [[ "${CALICO_PRESENT}" == "true" ]] &&
   kubectl get tigerastatus >/dev/null 2>&1; then

    info "Tigera status:"
    kubectl get tigerastatus 2>/dev/null |
        indent_output || true
fi

###############################################################################
# Summary
###############################################################################

END_TIME="$(date --iso-8601=seconds 2>/dev/null || date)"
DURATION_SECONDS="$(duration_seconds)"

print_header "Cluster Health Audit Summary"

echo "Start Time : ${START_TIME}"
echo "End Time   : ${END_TIME}"
echo "Duration   : ${DURATION_SECONDS} seconds"
echo "Context    : ${CURRENT_CONTEXT:-unknown}"
echo "Run ID     : ${RUN_SUFFIX}"
echo
printf 'PASS       : %s\n' "${PASS_COUNT}"
printf 'WARN       : %s\n' "${WARN_COUNT}"
printf 'FAIL       : %s\n' "${FAIL_COUNT}"
printf 'SKIP       : %s\n' "${SKIP_COUNT}"
echo

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
    echo "Overall Status: FAIL"
    echo "One or more critical health checks failed."
    echo "Review each [FAIL] result and its supporting output."
    exit 1
elif [[ "${WARN_COUNT}" -gt 0 ]]; then
    echo "Overall Status: PASS WITH WARNINGS"
    echo "No critical checks failed, but one or more items require review."
    exit 0
else
    echo "Overall Status: PASS"
    echo "All applicable cluster health checks passed."
    exit 0
fi

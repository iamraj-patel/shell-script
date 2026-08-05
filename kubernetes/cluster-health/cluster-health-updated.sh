#!/bin/bash

################################################################################
# Kubernetes Cluster Health Auditor
#
# Purpose:
#   Performs a practical health audit of a kubeadm-based Kubernetes cluster.
#
# Improvements:
#   - Uses API server /livez and /readyz checks
#   - Handles recent node reboot more intelligently
#   - Uses better DNS test logic
#   - Uses sudo for crictl when needed
#   - Avoids false DNS failures from interactive kubectl run behavior
#   - Performs Pod-to-Service networking test
#   - Checks CoreDNS, services, endpoints, PVCs, warnings, restarts, and metrics
################################################################################

set -uo pipefail

########################################
# Configuration
########################################

RESTART_WARN_THRESHOLD=5
RESTART_FAIL_THRESHOLD=15

SMOKE_NAMESPACE="cluster-health-smoke"
DNS_TEST_POD="dns-health-test"
NGINX_TEST_POD="nginx-health-test"
NGINX_TEST_SERVICE="nginx-health-svc"
CURL_TEST_POD="curl-health-test"

DNS_TEST_IMAGE="busybox:1.36"
CURL_TEST_IMAGE="curlimages/curl:latest"
NGINX_TEST_IMAGE="nginx:alpine"

DNS_TIMEOUT="90s"
POD_TIMEOUT="120s"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

RECENT_REBOOT_DETECTED="false"

########################################
# Output Helpers
########################################

print_header() {
    echo
    echo "=================================================="
    echo "$1"
    echo "=================================================="
}

print_section() {
    echo
    echo "[$1] $2"
}

pass() {
    echo "  [OK] $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

warn() {
    echo "  [WARN] $1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

fail() {
    echo "  [FAIL] $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

info() {
    echo "  [INFO] $1"
}

cleanup() {
    kubectl delete pod "${DNS_TEST_POD}" -n default --ignore-not-found=true >/dev/null 2>&1
    kubectl delete namespace "${SMOKE_NAMESPACE}" --ignore-not-found=true >/dev/null 2>&1
}

trap cleanup EXIT

########################################
# Start
########################################

print_header "Kubernetes Cluster Health Audit"
echo "Start Time : $(date)"
echo "User       : $(whoami)"
echo "Host       : $(hostname)"

########################################
# 1. kubectl Connectivity
########################################

print_section "1/15" "Checking kubectl connectivity"

if ! command -v kubectl >/dev/null 2>&1; then
    fail "kubectl is not installed or not in PATH."
    exit 1
fi

if kubectl cluster-info >/dev/null 2>&1; then
    pass "kubectl can communicate with the cluster."
else
    fail "kubectl cannot communicate with the cluster."
    exit 1
fi

info "Client and server version:"
kubectl version 2>/dev/null || true

########################################
# 2. API Server Health
########################################

print_section "2/15" "Checking API server livez and readyz"

if kubectl get --raw="/livez" >/dev/null 2>&1; then
    pass "API server livez endpoint is healthy."
else
    fail "API server livez endpoint failed."
fi

if kubectl get --raw="/readyz" >/dev/null 2>&1; then
    pass "API server readyz endpoint is healthy."
else
    fail "API server readyz endpoint failed."
    info "Verbose readyz output:"
    kubectl get --raw="/readyz?verbose" 2>/dev/null || true
fi

########################################
# 3. Node Ready Status
########################################

print_section "3/15" "Checking node Ready status"

NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)

if [[ "${NODE_COUNT}" -eq 0 ]]; then
    fail "No nodes found in the cluster."
else
    info "Total nodes detected: ${NODE_COUNT}"

    NOT_READY_NODES=$(kubectl get nodes --no-headers | awk '$2 != "Ready" {print $1 " " $2}')

    if [[ -z "${NOT_READY_NODES}" ]]; then
        pass "All nodes are Ready."
    else
        fail "One or more nodes are not Ready:"
        echo "${NOT_READY_NODES}"
    fi

    echo
    kubectl get nodes -o wide
fi

########################################
# 4. Node Pressure Conditions
########################################

print_section "4/15" "Checking node pressure conditions"

PRESSURE_ISSUES=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .status.conditions[*]}{.type}={.status}{" "}{end}{"\n"}{end}' \
    | grep -E 'MemoryPressure=True|DiskPressure=True|PIDPressure=True|NetworkUnavailable=True' || true)

if [[ -z "${PRESSURE_ISSUES}" ]]; then
    pass "No node pressure conditions detected."
else
    fail "Node pressure or network issue detected:"
    echo "${PRESSURE_ISSUES}"
fi

########################################
# 5. kube-system Pod Health
########################################

print_section "5/15" "Checking kube-system pod health"

KUBE_SYSTEM_BAD=$(kubectl get pods -n kube-system --no-headers 2>/dev/null \
    | awk '$3 !~ /Running|Completed/ {print}' || true)

if [[ -z "${KUBE_SYSTEM_BAD}" ]]; then
    pass "All kube-system pods are Running or Completed."
else
    fail "Problematic kube-system pods detected:"
    echo "${KUBE_SYSTEM_BAD}"
fi

echo
kubectl get pods -n kube-system -o wide

########################################
# 6. All Namespace Pod Health
########################################

print_section "6/15" "Checking pod health across all namespaces"

BAD_PODS=$(kubectl get pods -A --no-headers 2>/dev/null \
    | awk '$4 !~ /Running|Completed/ {print}' || true)

if [[ -z "${BAD_PODS}" ]]; then
    pass "No unhealthy pods found across namespaces."
else
    fail "Unhealthy pods found across namespaces:"
    echo "${BAD_PODS}"
fi

########################################
# 7. Pod Restart Count Check
########################################

print_section "7/15" "Checking pod restart counts"

RECENT_REBOOT_EVENT=$(kubectl get events -A --field-selector reason=Rebooted 2>/dev/null | grep -v "No resources found" || true)

if [[ -n "${RECENT_REBOOT_EVENT}" ]]; then
    RECENT_REBOOT_DETECTED="true"
    info "Recent node reboot event detected. Restart counts may be expected."
fi

RESTART_REPORT=$(kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{range .status.containerStatuses[*]}{.restartCount}{" "}{end}{"\n"}{end}' 2>/dev/null || true)

HIGH_RESTARTS=""
WARN_RESTARTS=""

while read -r namespace pod restarts_extra; do
    [[ -z "${namespace:-}" || -z "${pod:-}" ]] && continue

    TOTAL_RESTARTS=0

    for count in ${restarts_extra}; do
        if [[ "${count}" =~ ^[0-9]+$ ]]; then
            TOTAL_RESTARTS=$((TOTAL_RESTARTS + count))
        fi
    done

    if [[ "${TOTAL_RESTARTS}" -ge "${RESTART_FAIL_THRESHOLD}" ]]; then
        HIGH_RESTARTS+="${namespace}/${pod} restarts=${TOTAL_RESTARTS}"$'\n'
    elif [[ "${TOTAL_RESTARTS}" -ge "${RESTART_WARN_THRESHOLD}" ]]; then
        WARN_RESTARTS+="${namespace}/${pod} restarts=${TOTAL_RESTARTS}"$'\n'
    fi
done <<< "${RESTART_REPORT}"

if [[ -n "${HIGH_RESTARTS}" ]]; then
    if [[ "${RECENT_REBOOT_DETECTED}" == "true" ]]; then
        warn "High restart counts detected, but recent node reboot may explain them:"
        echo "${HIGH_RESTARTS}"
    else
        fail "Pods with high restart counts detected:"
        echo "${HIGH_RESTARTS}"
    fi
elif [[ -n "${WARN_RESTARTS}" ]]; then
    if [[ "${RECENT_REBOOT_DETECTED}" == "true" ]]; then
        info "Moderate restart counts detected after recent reboot:"
        echo "${WARN_RESTARTS}"
        pass "Restart counts are explainable by recent reboot."
    else
        warn "Pods with moderate restart counts detected:"
        echo "${WARN_RESTARTS}"
    fi
else
    pass "Pod restart counts are within expected range."
fi

########################################
# 8. CoreDNS Health
########################################

print_section "8/15" "Checking CoreDNS health"

COREDNS_PODS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null || true)

if [[ -z "${COREDNS_PODS}" ]]; then
    fail "No CoreDNS pods found using label k8s-app=kube-dns."
else
    COREDNS_BAD=$(echo "${COREDNS_PODS}" | awk '$3 != "Running" {print}' || true)

    if [[ -z "${COREDNS_BAD}" ]]; then
        pass "CoreDNS pods are Running."
    else
        fail "CoreDNS pods are not healthy:"
        echo "${COREDNS_BAD}"
    fi
fi

if kubectl get svc kube-dns -n kube-system >/dev/null 2>&1; then
    pass "kube-dns service exists."
else
    fail "kube-dns service is missing."
fi

COREDNS_ENDPOINTS=$(kubectl get endpoints kube-dns -n kube-system -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)

if [[ -n "${COREDNS_ENDPOINTS}" ]]; then
    pass "kube-dns service has endpoints: ${COREDNS_ENDPOINTS}"
else
    fail "kube-dns service has no endpoints."
fi

########################################
# 9. DNS Resolution Test
########################################

print_section "9/15" "Testing DNS resolution from inside the cluster"

kubectl delete pod "${DNS_TEST_POD}" -n default --ignore-not-found=true >/dev/null 2>&1

if kubectl run "${DNS_TEST_POD}" \
    --image="${DNS_TEST_IMAGE}" \
    --restart=Never \
    -n default \
    -- sleep 3600 >/dev/null 2>&1; then

    if kubectl wait --for=condition=Ready pod/"${DNS_TEST_POD}" -n default --timeout="${DNS_TIMEOUT}" >/dev/null 2>&1; then
        pass "DNS test pod is Ready."

        info "DNS test pod resolv.conf:"
        kubectl exec -n default "${DNS_TEST_POD}" -- cat /etc/resolv.conf 2>/dev/null || true

        DNS_OUTPUT_1=$(kubectl exec -n default "${DNS_TEST_POD}" -- nslookup kubernetes.default.svc.cluster.local 2>&1 || true)
        echo "${DNS_OUTPUT_1}"

        if echo "${DNS_OUTPUT_1}" | grep -qE 'Name:|Address [0-9]+:|Address:'; then
            pass "DNS resolves kubernetes.default.svc.cluster.local."
        else
            fail "DNS failed to resolve kubernetes.default.svc.cluster.local."
        fi

        DNS_OUTPUT_2=$(kubectl exec -n default "${DNS_TEST_POD}" -- nslookup kube-dns.kube-system.svc.cluster.local 2>&1 || true)
        echo "${DNS_OUTPUT_2}"

        if echo "${DNS_OUTPUT_2}" | grep -qE 'Name:|Address [0-9]+:|Address:'; then
            pass "DNS resolves kube-dns.kube-system.svc.cluster.local."
        else
            fail "DNS failed to resolve kube-dns.kube-system.svc.cluster.local."
        fi

    else
        fail "DNS test pod did not become Ready."
        kubectl describe pod "${DNS_TEST_POD}" -n default 2>/dev/null || true
    fi

else
    fail "Failed to create DNS test pod."
fi

kubectl delete pod "${DNS_TEST_POD}" -n default --ignore-not-found=true >/dev/null 2>&1

########################################
# 10. CNI / Pod-to-Service Networking Smoke Test
########################################

print_section "10/15" "Testing CNI and Pod-to-Service networking"

kubectl delete namespace "${SMOKE_NAMESPACE}" --ignore-not-found=true >/dev/null 2>&1

if kubectl create namespace "${SMOKE_NAMESPACE}" >/dev/null 2>&1; then
    pass "Created smoke-test namespace: ${SMOKE_NAMESPACE}"
else
    fail "Failed to create smoke-test namespace: ${SMOKE_NAMESPACE}"
fi

if kubectl run "${NGINX_TEST_POD}" \
    --image="${NGINX_TEST_IMAGE}" \
    --restart=Never \
    -n "${SMOKE_NAMESPACE}" >/dev/null 2>&1; then

    if kubectl wait --for=condition=Ready pod/"${NGINX_TEST_POD}" -n "${SMOKE_NAMESPACE}" --timeout="${POD_TIMEOUT}" >/dev/null 2>&1; then
        pass "nginx smoke-test pod is Ready."
    else
        fail "nginx smoke-test pod did not become Ready."
        kubectl describe pod "${NGINX_TEST_POD}" -n "${SMOKE_NAMESPACE}" 2>/dev/null || true
    fi

else
    fail "Failed to create nginx smoke-test pod."
fi

if kubectl expose pod "${NGINX_TEST_POD}" \
    --port=80 \
    --target-port=80 \
    --name="${NGINX_TEST_SERVICE}" \
    -n "${SMOKE_NAMESPACE}" >/dev/null 2>&1; then
    pass "Created nginx smoke-test service."
else
    fail "Failed to expose nginx smoke-test pod."
fi

SERVICE_ENDPOINTS=$(kubectl get endpoints "${NGINX_TEST_SERVICE}" -n "${SMOKE_NAMESPACE}" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)

if [[ -n "${SERVICE_ENDPOINTS}" ]]; then
    pass "Smoke-test service has endpoint: ${SERVICE_ENDPOINTS}"
else
    fail "Smoke-test service has no endpoints."
fi

if kubectl run "${CURL_TEST_POD}" \
    --image="${CURL_TEST_IMAGE}" \
    --restart=Never \
    -n "${SMOKE_NAMESPACE}" \
    --command -- curl -fsS --max-time 10 "http://${NGINX_TEST_SERVICE}.${SMOKE_NAMESPACE}.svc.cluster.local" >/dev/null 2>&1; then
    pass "Pod-to-Service networking works using full service FQDN."
else
    fail "Pod-to-Service networking test failed using full service FQDN."
fi

kubectl delete namespace "${SMOKE_NAMESPACE}" --ignore-not-found=true >/dev/null 2>&1

########################################
# 11. Service Endpoint Health
########################################

print_section "11/15" "Checking services without endpoints"

SERVICES_WITHOUT_ENDPOINTS=""

while read -r namespace service service_type; do
    [[ -z "${namespace:-}" || -z "${service:-}" ]] && continue

    if [[ "${service_type}" == "ExternalName" ]]; then
        continue
    fi

    if [[ "${service}" == "kubernetes" && "${namespace}" == "default" ]]; then
        continue
    fi

    ENDPOINTS=$(kubectl get endpoints "${service}" -n "${namespace}" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)

    if [[ -z "${ENDPOINTS}" ]]; then
        SERVICES_WITHOUT_ENDPOINTS+="${namespace}/${service}"$'\n'
    fi
done < <(kubectl get svc -A --no-headers 2>/dev/null | awk '{print $1, $2, $3}')

if [[ -z "${SERVICES_WITHOUT_ENDPOINTS}" ]]; then
    pass "All checked services have endpoints."
else
    warn "Some services have no endpoints:"
    echo "${SERVICES_WITHOUT_ENDPOINTS}"
fi

########################################
# 12. PVC Health
########################################

print_section "12/15" "Checking PersistentVolumeClaim health"

PVC_OUTPUT=$(kubectl get pvc -A --no-headers 2>/dev/null || true)

if [[ -z "${PVC_OUTPUT}" ]]; then
    info "No PVCs found in the cluster."
    pass "PVC check skipped because no PVCs exist."
else
    BAD_PVCS=$(echo "${PVC_OUTPUT}" | awk '$4 != "Bound" {print}' || true)

    if [[ -z "${BAD_PVCS}" ]]; then
        pass "All PVCs are Bound."
    else
        fail "PVCs not in Bound state:"
        echo "${BAD_PVCS}"
    fi
fi

########################################
# 13. Recent Warning Events
########################################

print_section "13/15" "Checking recent Warning events"

WARNING_EVENTS=$(kubectl get events -A \
    --field-selector type=Warning \
    --sort-by='.metadata.creationTimestamp' 2>/dev/null | tail -n 20 || true)

if [[ -z "${WARNING_EVENTS}" || "${WARNING_EVENTS}" == *"No resources found"* ]]; then
    pass "No Warning events found."
else
    if [[ "${RECENT_REBOOT_DETECTED}" == "true" ]]; then
        warn "Recent Warning events detected. Recent node reboot may explain some temporary probe failures:"
    else
        warn "Recent Warning events detected. Showing latest 20:"
    fi

    echo "${WARNING_EVENTS}"
fi

########################################
# 14. Container Runtime Check
########################################

print_section "14/15" "Checking container runtime with crictl"

if command -v crictl >/dev/null 2>&1; then

    if crictl info >/dev/null 2>&1; then
        pass "crictl can communicate with the container runtime as current user."
        crictl version 2>/dev/null || true

    elif command -v sudo >/dev/null 2>&1 && sudo -n crictl info >/dev/null 2>&1; then
        pass "crictl can communicate with the container runtime using sudo."
        sudo crictl version 2>/dev/null || true

    else
        fail "crictl cannot communicate with the container runtime."
        info "Try manually:"
        echo "  sudo crictl info"
        echo "  sudo systemctl status containerd --no-pager"
        echo "  cat /etc/crictl.yaml"
    fi

else
    warn "crictl is not installed. Skipping runtime-level CRI check."
fi

########################################
# 15. Metrics Server Check
########################################

print_section "15/15" "Checking metrics server availability"

if kubectl get apiservice v1beta1.metrics.k8s.io >/dev/null 2>&1; then
    METRICS_STATUS=$(kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)

    if [[ "${METRICS_STATUS}" == "True" ]]; then
        pass "Metrics API is available."

        if kubectl top nodes >/dev/null 2>&1; then
            info "Node resource usage:"
            kubectl top nodes || true
        else
            warn "Metrics API exists, but kubectl top nodes failed."
        fi
    else
        warn "Metrics API exists but is not Available."
        kubectl get apiservice v1beta1.metrics.k8s.io -o wide || true
    fi
else
    warn "Metrics server is not installed. Skipping resource usage checks."
fi

########################################
# Summary
########################################

print_header "Cluster Health Audit Summary"

echo "End Time : $(date)"
echo "Pass     : ${PASS_COUNT}"
echo "Warn     : ${WARN_COUNT}"
echo "Fail     : ${FAIL_COUNT}"

echo
if [[ "${FAIL_COUNT}" -eq 0 ]]; then
    echo "Overall Status: PASS"
    echo "Cluster appears healthy based on this audit."
    exit 0
else
    echo "Overall Status: FAIL"
    echo "One or more critical checks failed. Review the failed sections above."
    exit 1
fi

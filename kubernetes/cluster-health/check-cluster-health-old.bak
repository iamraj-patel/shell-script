#!/bin/bash

# --- Kubernetes Cluster Health Check Script ---
# This script performs a series of checks to validate the health of a Kubernetes cluster.
# It requires kubectl to be configured to connect to the cluster.

# Exit immediately if a command exits with a non-zero status.
set -e

# ANSI escape codes for colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print a header
print_header() {
    echo -e "${BLUE}--- $1 ---${NC}"
}

# Function to print a success message
print_success() {
    echo -e "${GREEN}✓ Success: $1${NC}"
}

# Function to print a failure message and exit
print_failure() {
    echo -e "${RED}✗ Failure: $1${NC}"
    echo "Exiting script due to failure."
    exit 1
}

# --- Cleanup previous test resources if they exist ---
print_header "Cleaning up previous test resources..."
kubectl delete pod test-pod --ignore-not-found=true > /dev/null || true
kubectl delete svc test-pod --ignore-not-found=true > /dev/null || true
echo "Cleanup complete."
echo ""

# --- Check 1: Node Health ---
print_header "Checking Node Status..."
node_count=$(kubectl get nodes | awk 'NR>1 {print $2}' | wc -l)
ready_nodes=$(kubectl get nodes | awk 'NR>1 {print $2}' | grep "Ready" | wc -l)

if [[ "$node_count" -eq "$ready_nodes" && "$node_count" -gt 0 ]]; then
    print_success "All $ready_nodes nodes are Ready."
else
    kubectl get nodes
    print_failure "Some nodes are not Ready."
fi
echo ""

# --- Check 2: Control Plane and CNI Pods ---
print_header "Checking Core System Pods..."

# Count total pods and total running pods in kube-system
total_pods=$(kubectl get pods -n kube-system --field-selector=status.phase!=Succeeded --no-headers | wc -l)
running_pods=$(kubectl get pods -n kube-system --field-selector=status.phase!=Succeeded --no-headers | grep "Running" | wc -l)

if [[ "$total_pods" -eq "$running_pods" && "$total_pods" -gt 0 ]]; then
    print_success "All $total_pods pods in 'kube-system' are Running."
else
    # Only show pods that are not running
    echo "Found pods that are not in a 'Running' state:"
    kubectl get pods -n kube-system --field-selector=status.phase!=Succeeded | grep -v "Running"
    print_failure "Not all core system pods are ready."
fi
echo ""

# --- Check 3: CNI (Calico) Health ---
print_header "Checking CNI Health..."
desired_calico_nodes=$(kubectl get ds calico-node -n kube-system -o jsonpath='{.status.desiredNumberScheduled}')
ready_calico_nodes=$(kubectl get ds calico-node -n kube-system -o jsonpath='{.status.numberReady}')

if [[ "$desired_calico_nodes" == "$ready_calico_nodes" ]]; then
    print_success "Calico CNI DaemonSet is fully ready ($ready_calico_nodes/$desired_calico_nodes nodes)."
else
    echo "Calico DaemonSet is not fully ready."
    kubectl get ds calico-node -n kube-system
    print_failure "Calico CNI is not healthy."
fi
echo ""

# --- Check 4: DNS Functionality and Service Connectivity ---
print_header "Testing DNS and Service Connectivity..."
echo "1. Creating a test pod 'test-pod'..."
# Use `kubectl run` with the --expose flag to create both a Pod and a Service
kubectl run test-pod --image=nginx:alpine --port=80 --expose=true > /dev/null
sleep 10

# Wait for the pod to be running
kubectl wait --for=condition=ready pod/test-pod --timeout=60s > /dev/null || print_failure "Test pod failed to become ready."
print_success "Test pod 'test-pod' is ready."

# Wait for the service to be ready and get its IP
echo "2. Waiting for the service IP..."
service_ip=$(kubectl get svc test-pod -o jsonpath='{.spec.clusterIP}')
if [[ -z "$service_ip" ]]; then
    print_failure "Failed to get ClusterIP for test service."
fi
print_success "Test service 'test-pod' ClusterIP is $service_ip."

# Test connectivity to the service IP
echo "3. Testing connectivity to the service IP from the host..."
curl --max-time 10 $service_ip:80 -s > /dev/null
if [[ $? -eq 0 ]]; then
    print_success "Connectivity to service IP $service_ip is working."
else
    print_failure "Failed to connect to test service IP $service_ip. Networking is not working."
fi

# Test DNS resolution from inside the pod
echo "4. Testing DNS resolution from inside the pod..."
dns_lookup_result=$(kubectl exec test-pod -- nslookup kubernetes.default.svc.cluster.local || true)
if [[ $dns_lookup_result == *"Address: 10.96.0.1"* ]]; then
    print_success "DNS resolution is working inside the pod."
else
    echo "nslookup output:"
    echo -e "${RED}$dns_lookup_result${NC}"
    print_failure "DNS resolution failed inside the pod."
fi
echo ""

# --- Final Cleanup and Summary ---
print_header "Cleaning up test resources..."
kubectl delete pod test-pod --grace-period=0 --force > /dev/null
kubectl delete svc test-pod > /dev/null
print_success "All test resources cleaned up."
echo ""
echo -e "${BLUE}--- ALL CHECKS PASSED ---${NC}"
echo "Your Kubernetes cluster appears to be healthy and fully functional."

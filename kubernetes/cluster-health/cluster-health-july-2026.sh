#!/bin/bash

# Cluster Health Auditor
# Purpose: Validate cluster state, DNS, CNI, and control plane health.

echo "=== Starting Cluster Health Audit: $(date) ==="

# 1. Check Node Status
echo -e "\n[1/5] Checking Node Status..."
if [[ $(kubectl get nodes --no-headers | grep -v "Ready" | wc -l) -eq 0 ]]; then
    echo "  [OK] All nodes are Ready."
else
    echo "  [FAIL] Some nodes are not Ready:"
    kubectl get nodes | grep -v "Ready"
fi

# 2. Check Critical System Pods
echo -e "\n[2/5] Checking System Components (kube-system)..."
# Check for any pods in crashloop or not running
FAILED_PODS=$(kubectl get pods -n kube-system --no-headers | grep -vE "Running|Completed" | wc -l)
if [[ $FAILED_PODS -eq 0 ]]; then
    echo "  [OK] All system pods are stable."
else
    echo "  [FAIL] Issues detected in system pods:"
    kubectl get pods -n kube-system --no-headers | grep -vE "Running|Completed"
fi

# 3. Test DNS Resolution (Internal)
echo -e "\n[3/5] Testing DNS Resolution..."
DNS_TEST=$(kubectl run --rm -it dns-test --image=busybox:1.28 --restart=Never -n default -- nslookup kubernetes.default 2>/dev/null)
if [[ $? -eq 0 ]]; then
    echo "  [OK] DNS resolution is functioning."
else
    echo "  [FAIL] DNS resolution failed."
fi

# 4. Perform Network Smoke Test
echo -e "\n[4/5] Testing CNI / Pod Networking..."
kubectl create ns smoke-test --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
kubectl run nginx-test --image=nginx:alpine -n smoke-test --restart=Never >/dev/null 2>&1
sleep 5 # Give it a moment to pull image
kubectl expose pod nginx-test --port=80 --name=nginx-svc -n smoke-test >/dev/null 2>&1
sleep 2

# Verify reachability
if kubectl run curl-test --image=curlimages/curl --restart=Never -n smoke-test -- curl -s http://nginx-svc >/dev/null 2>&1; then
    echo "  [OK] Pod-to-Service networking is working."
else
    echo "  [FAIL] Networking test failed."
fi
# Cleanup
kubectl delete ns smoke-test >/dev/null 2>&1

# 5. Check Cluster Events (Last 2 minutes)
echo -e "\n[5/5] Checking Recent Warnings (Last 2 minutes)..."

# Get current time in epoch
CURRENT_TIME=$(date +%s)

# Filter events: Only show warnings that happened in the last 120 seconds
WARNINGS=$(kubectl get events -A --sort-by='.metadata.creationTimestamp' | awk -v now="$CURRENT_TIME" '
    /Warning/ {
        # This is a simplified check. We compare the "AGE" column.
        # If age contains "m", check if it is < 2.
        age = $2;
        if (age ~ /^[0-9]+m$/) {
            split(age, a, "m");
            if (a[1] < 2) print $0;
        } else if (age ~ /s/) {
            print $0;
        }
    }
')

if [[ -z "$WARNINGS" ]]; then
    echo "  [OK] No major warnings in the last 2 minutes."
else
    echo "  [!] Recent Warnings (Last 2m):"
    echo "$WARNINGS"
fi

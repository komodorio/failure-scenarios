#!/bin/bash

# Quick diagnostic script for userservice after NetworkPolicy scenario

set -euo pipefail

NAMESPACE="${NAMESPACE:-anthos-bank-${USER}}"

echo "=========================================="
echo "  userservice Diagnostic Check"
echo "=========================================="
echo ""

echo "1. Pod Status:"
kubectl get pods -l app=userservice -n "${NAMESPACE}"
echo ""

echo "2. NetworkPolicy Status:"
if kubectl get networkpolicy block-userservice-to-accounts-db -n "${NAMESPACE}" 2>/dev/null; then
    echo "⚠️  NetworkPolicy still exists!"
else
    echo "✅ NetworkPolicy removed"
fi
echo ""

echo "3. Connectivity Test from userservice to accounts-db:"
POD=$(kubectl get pods -l app=userservice -n "${NAMESPACE}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD" ]; then
    echo "Testing from pod: $POD"
    kubectl exec -n "${NAMESPACE}" "$POD" -- python3 -c "import socket; socket.create_connection(('accounts-db', 5432), timeout=2); print('✅ Connection succeeded')" 2>&1 || echo "❌ Connection failed"
else
    echo "❌ No userservice pod found"
fi
echo ""

echo "4. Readiness Probe Events (last 5):"
kubectl get events -n "${NAMESPACE}" --field-selector involvedObject.name="$POD" \
    --sort-by='.lastTimestamp' 2>/dev/null | grep -i "readiness\|unhealthy" | tail -5 || echo "No probe events found"
echo ""

echo "5. Pod Description (Conditions):"
kubectl get pod "$POD" -n "${NAMESPACE}" -o jsonpath='{.status.conditions[*].type}{"\n"}{.status.conditions[*].status}' 2>/dev/null
echo ""
echo ""

echo "6. Deployment Status:"
kubectl get deployment userservice -n "${NAMESPACE}"
echo ""


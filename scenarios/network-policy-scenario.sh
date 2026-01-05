#!/bin/bash

# NetworkPolicy Scenario - Database Connection Blocked
# This script creates a NetworkPolicy that blocks userservice from accessing accounts-db
#
# Usage:
#   ./network-policy-scenario.sh          # Inject failure (default)
#   ./network-policy-scenario.sh inject   # Inject failure
#   ./network-policy-scenario.sh revert   # Revert failure

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="NetworkPolicy"
SCENARIO_DESCRIPTION="Creates a NetworkPolicy that blocks userservice from accessing accounts-db"
NETWORK_POLICY_NAME="accountdb-acl"

# ==============================================================================
# SHARED FUNCTIONS
# ==============================================================================

# Function to print scenario description
print_scenario_description() {
    echo ""
    echo "=========================================="
    echo "  ${SCENARIO_NAME} Scenario"
    echo "=========================================="
    echo ""
    echo "Description:"
    echo "  This scenario creates a NetworkPolicy that blocks network traffic from"
    echo "  userservice to accounts-db. This simulates a network isolation misconfiguration"
    echo "  where a security policy accidentally blocks legitimate service-to-service"
    echo "  communication, causing authentication and user profile operations to fail."
    echo ""
    echo "Affected Services:"
    echo "  • accounts-db: NetworkPolicy blocks ingress from userservice"
    echo "  • userservice: Cannot connect to accounts-db (connection timeout)"
    echo "  • frontend: User login and profile operations fail"
    echo ""
    echo "Expected Behavior:"
    echo "  • NetworkPolicy applied to accounts-db"
    echo "  • userservice connections to accounts-db timeout"
    echo "  • User authentication fails with database connection errors"
    echo "  • Frontend shows 'Service Unavailable' or 'Connection Timeout' errors"
    echo "  • contacts service may still work (not blocked by policy)"
    echo ""
    echo "Observable Symptoms:"
    echo "  • userservice logs show database connection timeouts"
    echo "  • userservice logs: 'could not connect to server' or 'connection refused'"
    echo "  • Frontend login attempts fail"
    echo "  • kubectl describe networkpolicy shows the blocking rule"
    echo "  • accounts-db pod is healthy but unreachable from userservice"
    echo "  • Other services (contacts) can still reach accounts-db normally"
    echo ""
    echo "Real-World Scenarios This Represents:"
    echo "  • Overly restrictive NetworkPolicy accidentally deployed"
    echo "  • Security policy misconfiguration in multi-tenant clusters"
    echo "  • Service mesh authorization rules blocking legitimate traffic"
    echo "  • Kubernetes Network Plugin (CNI) misconfiguration"
    echo "  • Zero-trust network policy gone wrong"
    echo "  • Copy-paste error in NetworkPolicy selectors"
    echo ""
    echo "=========================================="
    echo ""
}

# Function to check if NetworkPolicy is supported
check_network_policy_support() {
    print_info "Checking if NetworkPolicy is supported in this cluster..."

    # Try to get network policies (will fail if not supported)
    if ! kubectl get networkpolicies -n "${NAMESPACE}" >/dev/null 2>&1; then
        print_warning "NetworkPolicy API may not be available in this cluster"
        print_warning "This scenario requires a CNI plugin that supports NetworkPolicy (e.g., Calico, Cilium, Weave)"
        print_warning "Continuing anyway - if NetworkPolicy is not supported, it will be created but not enforced"
    else
        print_success "NetworkPolicy API is available"
    fi
}

# ==============================================================================
# INJECT FAILURE
# ==============================================================================

inject_failure() {
    print_info "Creating NetworkPolicy to block userservice from accessing accounts-db..."

    # Create a NetworkPolicy that:
    # 1. Applies to accounts-db pods (using label selector)
    # 2. Allows ingress from contacts (still works)
    # 3. Blocks ingress from userservice (causes failure)
    kubectl apply -n "${NAMESPACE}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${NETWORK_POLICY_NAME}
  namespace: ${NAMESPACE}
spec:
  # Apply to accounts-db pods
  podSelector:
    matchLabels:
      app: accounts-db
  policyTypes:
    - Ingress
  ingress:
    # Allow contacts to still access accounts-db (this works fine)
    - from:
      - podSelector:
          matchLabels:
            app: contacts
      ports:
      - protocol: TCP
        port: 5432
    # Allow DNS queries (required for service discovery)
    - from:
      - namespaceSelector:
          matchLabels:
            name: kube-system
      ports:
      - protocol: UDP
        port: 53
    # Explicitly block userservice by not including it in allowed list
    # (implicit deny-all for any pod not matching the above rules)
EOF

    print_success "NetworkPolicy created successfully"
    print_warning "userservice is now blocked from accessing accounts-db"

    sleep 2

    print_info "NetworkPolicy details:"
    kubectl get networkpolicy "${NETWORK_POLICY_NAME}" -n "${NAMESPACE}" -o wide 2>/dev/null || true
}

# ==============================================================================
# REVERT FAILURE
# ==============================================================================

revert_failure() {
    print_info "Removing NetworkPolicy to restore userservice → accounts-db connectivity..."

    if kubectl get networkpolicy "${NETWORK_POLICY_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
        kubectl delete networkpolicy "${NETWORK_POLICY_NAME}" -n "${NAMESPACE}"
        print_success "NetworkPolicy '${NETWORK_POLICY_NAME}' removed"

        # Wait for userservice to become Ready again
        print_info "Waiting for userservice readiness probe to pass..."
        local timeout=60
        local elapsed=0

        while [ $elapsed -lt $timeout ]; do
            local ready_pods=$(kubectl get pods -n "${NAMESPACE}" -l app=userservice -o jsonpath='{.items[*].status.containerStatuses[*].ready}' 2>/dev/null | grep -o "true" | wc -l || echo "0")

            if [ "$ready_pods" -gt 0 ]; then
                print_success "userservice pod is now Ready (1/1)"
                break
            fi

            sleep 2
            elapsed=$((elapsed + 2))
        done

        if [ $elapsed -ge $timeout ]; then
            print_warning "Timeout waiting for userservice to become Ready"
            print_info "Check pod status with: kubectl get pods -l app=userservice -n ${NAMESPACE}"
        fi
    else
        print_info "NetworkPolicy '${NETWORK_POLICY_NAME}' not found (already removed or never created)"
    fi
}

# ==============================================================================
# MAIN ACTIONS
# ==============================================================================

# Action: inject
action_inject() {
    # Print scenario description
    print_scenario_description

    # Prerequisite checks
    check_manifests
    check_deployment
    create_backup

    # Check NetworkPolicy support
    check_network_policy_support

    # Inject the failure
    echo ""
    inject_failure

    echo ""
    print_success "NetworkPolicy scenario injected successfully!"
    echo ""
    print_warning "IMPORTANT: userservice pod will become NotReady (0/1) soon!"
    echo ""
    print_info "The userservice readiness probe checks database connectivity"
    print_info "NetworkPolicy is now blocking userservice → accounts-db"
    print_info "The probe will fail and pod will show as NotReady (0/1)"
    echo ""
    print_info "To monitor the effects:"
    echo "  • kubectl get pods -l app=userservice -n ${NAMESPACE} -w"
    echo "    (Watch pod go from 1/1 Ready → 0/1 NotReady)"
    echo ""
    echo "  • kubectl describe pod -l app=userservice -n ${NAMESPACE}"
    echo "    (Shows: 'Readiness probe failed' in events)"
    echo ""
    echo "  • kubectl logs -f deployment/userservice -n ${NAMESPACE}"
    echo "    (Container still running, but probe fails)"
    echo ""
    echo "  • kubectl get networkpolicies -n ${NAMESPACE}"
    echo "  • kubectl describe networkpolicy ${NETWORK_POLICY_NAME} -n ${NAMESPACE}"
    echo ""
    print_warning "Expected behavior:"
    echo "  • userservice pod shows as Running but NotReady (0/1)"
    echo "  • Readiness probe fails: 'nc -zv accounts-db 5432' times out"
    echo "  • Pod is removed from service endpoints (no traffic routed)"
    echo "  • Frontend login attempts fail (service has no healthy endpoints)"
    echo "  • contacts service should still work normally (not affected by NetworkPolicy)"
    echo ""
    print_info "To test connectivity manually:"
    echo "  • kubectl exec -it deployment/userservice -n ${NAMESPACE} -- python3 -c \"import socket; socket.create_connection(('accounts-db', 5432), timeout=2); print('Connected')\""
    echo "    (Should timeout or fail when blocked)"
    echo ""
    echo "  • kubectl exec -it deployment/contacts -n ${NAMESPACE} -- python3 -c \"import socket; socket.create_connection(('accounts-db', 5432), timeout=2); print('Connected')\""
    echo "    (Should show: 'Connected' - contacts still works!)"
    echo ""
    print_info "To revert this scenario, run: $0 revert"
    echo ""
}

# Action: revert
action_revert() {
    echo ""
    echo "=========================================="
    echo "  Reverting ${SCENARIO_NAME} Scenario"
    echo "=========================================="
    echo ""

    # Revert the failure
    revert_failure

    echo ""
    print_success "${SCENARIO_NAME} scenario reverted successfully!"
    echo ""
    print_info "Verification:"
    echo "  • kubectl get pods -l app=userservice -n ${NAMESPACE}"
    echo "    (Should show: Running and Ready 1/1)"
    echo ""
    echo "  • kubectl get networkpolicies -n ${NAMESPACE}"
    echo "    (Should NOT show: ${NETWORK_POLICY_NAME})"
    echo ""
}

# ==============================================================================
# AUTO-APPLY
# ==============================================================================

# Override auto-apply to inject the scenario
action_auto_apply() {
    action_inject
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

# Handle command line arguments using common handler
handle_scenario_command "$@"

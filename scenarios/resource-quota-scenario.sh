#!/bin/bash

# ResourceQuota Exhaustion Scenario
# This script creates a restrictive ResourceQuota causing pod evictions and crash loops
#
# Usage:
#   ./resource-quota-scenario.sh          # Inject failure (default)
#   ./resource-quota-scenario.sh inject   # Inject failure
#   ./resource-quota-scenario.sh revert   # Revert failure

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="ResourceQuota"
SCENARIO_DESCRIPTION="Creates a restrictive ResourceQuota that limits namespace resources and causes pod creation failures"

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
    echo "  This scenario creates a restrictive ResourceQuota that limits CPU and memory"
    echo "  resources for the entire namespace to unreasonably low values (100m CPU, 128Mi"
    echo "  memory total). It then scales the userservice deployment to 5 replicas to"
    echo "  trigger pod creation failures. New pods fail to schedule due to quota limits,"
    echo "  causing the deployment to become unhealthy and unavailable."
    echo ""
    echo "Affected Services:"
    echo "  • userservice: Scaled to 5 replicas (will fail to create new pods)"
    echo "  • All deployments in the namespace"
    echo "  • Pods fail to schedule due to quota limits"
    echo "  • Existing pods get evicted when they exceed quota"
    echo ""
    echo "Expected Behavior:"
    echo "  • ResourceQuota created with restrictive limits (100m CPU, 128Mi memory)"
    echo "  • userservice scaled to 5 replicas to trigger pod creation"
    echo "  • New userservice pods fail to schedule with 'Forbidden' errors"
    echo "  • userservice deployment becomes unhealthy (e.g., 1/5 ready)"
    echo "  • Deployment shows ReplicaFailure: FailedCreate"
    echo "  • Existing pods may be evicted if they exceed quota"
    echo "  • Services become unavailable or degraded"
    echo ""
    echo "Observable Symptoms:"
    echo "  • userservice deployment shows unhealthy state (e.g., READY 1/5)"
    echo "  • kubectl get events shows 'FailedCreate' with quota exceeded errors"
    echo "  • kubectl describe deployment userservice shows ReplicaFailure: FailedCreate"
    echo "  • kubectl get resourcequota shows quota usage at 100%+"
    echo "  • New pods cannot be created due to quota limits"
    echo "  • Services become unavailable or degraded"
    echo ""
    echo "Real-World Scenarios This Represents:"
    echo "  • Accidental ResourceQuota misconfiguration"
    echo "  • Namespace resource limits set too low"
    echo "  • Multi-tenant cluster with strict resource isolation"
    echo "  • Cost optimization gone wrong"
    echo ""
    echo "=========================================="
    echo ""
}

# ==============================================================================
# INJECT FAILURE
# ==============================================================================

inject_failure() {
    print_info "Creating restrictive ResourceQuota..."

    # Create ResourceQuota with very restrictive limits
    kubectl apply -n "${NAMESPACE}" -f - <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: crash-loop-quota
  namespace: ${NAMESPACE}
spec:
  hard:
    requests.cpu: "100m"
    requests.memory: 128Mi
    limits.cpu: "100m"
    limits.memory: 128Mi
EOF

    print_success "ResourceQuota created successfully"
    print_info "ResourceQuota limits: 100m CPU, 128Mi memory (total for namespace)"
    sleep 2

    print_info "Checking ResourceQuota status..."
    kubectl get resourcequota crash-loop-quota -n "${NAMESPACE}" -o wide

    echo ""
    print_info "Scaling userservice to 5 replicas to trigger pod creation failures..."
    kubectl scale deployment userservice --replicas=5 -n "${NAMESPACE}"
    print_success "userservice scaled to 5 replicas"

    echo ""
    print_warning "New userservice pods will fail to schedule due to quota limits"
    print_info "Monitoring pod status..."
    sleep 3

    kubectl get pods -n "${NAMESPACE}" -l app=userservice -o wide
    echo ""
    print_info "Checking userservice deployment status..."
    kubectl get deployment userservice -n "${NAMESPACE}" -o wide
}

# ==============================================================================
# REVERT FAILURE
# ==============================================================================

revert_failure() {
    print_info "Removing restrictive ResourceQuota..."

    if kubectl get resourcequota crash-loop-quota -n "${NAMESPACE}" >/dev/null 2>&1; then
        kubectl delete resourcequota crash-loop-quota -n "${NAMESPACE}" 2>/dev/null || true
        print_success "ResourceQuota 'crash-loop-quota' removed"
    else
        print_info "No restrictive ResourceQuota found"
    fi

    echo ""
    print_info "Restoring userservice replica count..."
    if kubectl get deployment userservice -n "${NAMESPACE}" >/dev/null 2>&1; then
        CURRENT_REPLICAS=$(kubectl get deployment userservice -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        if [ "${CURRENT_REPLICAS}" != "1" ]; then
            kubectl scale deployment userservice --replicas=1 -n "${NAMESPACE}" 2>/dev/null || true
            print_success "userservice scaled back to 1 replica"
        else
            print_info "userservice already at 1 replica"
        fi
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

    # Inject the failure
    echo ""
    inject_failure

    echo ""
    print_success "${SCENARIO_NAME} scenario injected successfully!"
    echo ""
    print_info "To monitor the effects:"
    echo "  • kubectl get resourcequota -n ${NAMESPACE}"
    echo "  • kubectl describe resourcequota crash-loop-quota -n ${NAMESPACE}"
    echo "  • kubectl get pods -n ${NAMESPACE} -w"
    echo "  • kubectl describe pod <pod-name> -n ${NAMESPACE}"
    echo "  • kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' | grep -i quota"
    echo ""
    print_warning "userservice should show unhealthy state (e.g., READY 1/5) with new pods failing to create"
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
    echo "  • kubectl get resourcequota -n ${NAMESPACE}"
    echo "    (Should NOT show: crash-loop-quota)"
    echo ""
    echo "  • kubectl get deployment userservice -n ${NAMESPACE}"
    echo "    (Should show: READY 1/1)"
    echo ""
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

# Handle command line arguments using common handler
handle_scenario_command "$@"

#!/bin/bash

# LimitRange Failure Scenario
# This script creates a restrictive LimitRange that prevents contacts deployment from restarting
#
# Usage:
#   ./limit-range-contacts-scenario.sh          # Inject failure (default)
#   ./limit-range-contacts-scenario.sh inject   # Inject failure
#   ./limit-range-contacts-scenario.sh revert   # Revert failure

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="LimitRange"
SCENARIO_DESCRIPTION="Creates a restrictive LimitRange that prevents contacts deployment from restarting"

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
    echo "  This scenario creates a restrictive LimitRange that sets maximum resource limits"
    echo "  below what the contacts deployment requires. It then deletes the contacts pods,"
    echo "  causing them to fail to restart because their resource requests exceed the"
    echo "  LimitRange maximums. This simulates a misconfigured namespace policy that"
    echo "  prevents pods from being created."
    echo ""
    echo "Affected Services:"
    echo "  • contacts: Pods cannot restart due to LimitRange restrictions"
    echo "  • All new pods in the namespace (if they exceed limits)"
    echo ""
    echo "Expected Behavior:"
    echo "  • LimitRange created with restrictive maximum limits (200m CPU, 128Mi memory)"
    echo "  • Existing contacts pods are deleted"
    echo "  • New contacts pods fail to be created"
    echo "  • Pod creation fails with 'Forbidden' error due to LimitRange violation"
    echo "  • Deployment shows ReplicaFailure: FailedCreate"
    echo "  • contacts service becomes unavailable"
    echo ""
    echo "Observable Symptoms:"
    echo "  • contacts deployment shows 0/1 ready replicas"
    echo "  • kubectl get events shows 'FailedCreate' with LimitRange exceeded errors"
    echo "  • kubectl describe deployment contacts shows ReplicaFailure: FailedCreate"
    echo "  • kubectl get limitrange shows the restrictive limits"
    echo "  • New pods cannot be created due to LimitRange validation"
    echo "  • contacts service becomes unavailable"
    echo ""
    echo "Real-World Scenarios This Represents:"
    echo "  • Accidental LimitRange misconfiguration"
    echo "  • Namespace policy set too restrictive"
    echo "  • Multi-tenant cluster with strict resource policies"
    echo "  • Security/compliance policies blocking pod creation"
    echo ""
    echo "=========================================="
    echo ""
}

# ==============================================================================
# INJECT FAILURE
# ==============================================================================

inject_failure() {
    print_info "Creating restrictive LimitRange..."

    # Create LimitRange with maximum limits below contacts requirements
    # contacts requires: cpu: 100m request, 250m limit; memory: 64Mi request, 128Mi limit
    # LimitRange sets max: cpu: 200m, memory: 128Mi (below contacts limits)
    kubectl apply -n "${NAMESPACE}" -f - <<EOF
apiVersion: v1
kind: LimitRange
metadata:
  name: restrictive-limit-range
  namespace: ${NAMESPACE}
spec:
  limits:
  - type: Pod
    max:
      cpu: "200m"
      memory: "128Mi"
    min:
      cpu: "10m"
      memory: "16Mi"
EOF

    print_success "LimitRange created successfully"
    print_info "LimitRange maximum limits: 200m CPU, 128Mi memory (below contacts limits)"
    sleep 2

    print_info "Checking LimitRange status..."
    kubectl get limitrange restrictive-limit-range -n "${NAMESPACE}" -o wide
    echo ""

    print_info "Deleting contacts pods to trigger restart failure..."

    # Get all contacts pods
    local CONTACTS_PODS
    CONTACTS_PODS=$(kubectl get pods -n "${NAMESPACE}" -l app=contacts -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$CONTACTS_PODS" ]; then
        for pod in $CONTACTS_PODS; do
            print_info "Deleting pod: ${pod}"
            kubectl delete pod "${pod}" -n "${NAMESPACE}" --grace-period=0 --force 2>/dev/null || true
        done
        print_success "contacts pods deleted"
    else
        print_warning "No contacts pods found to delete"
    fi

    echo ""
    print_warning "New contacts pods will fail to create due to LimitRange restrictions"
    print_info "Monitoring pod status..."
    sleep 5

    kubectl get pods -n "${NAMESPACE}" -l app=contacts -o wide
    echo ""
    print_info "Checking contacts deployment status..."
    kubectl get deployment contacts -n "${NAMESPACE}" -o wide
    echo ""
    print_info "Checking events for LimitRange violations..."
    kubectl get events -n "${NAMESPACE}" --sort-by='.lastTimestamp' | grep -i "limitrange\|contacts" | tail -10 || true
}

# ==============================================================================
# REVERT FAILURE
# ==============================================================================

revert_failure() {
    print_info "Removing restrictive LimitRange..."

    if kubectl get limitrange restrictive-limit-range -n "${NAMESPACE}" >/dev/null 2>&1; then
        kubectl delete limitrange restrictive-limit-range -n "${NAMESPACE}" 2>/dev/null || true
        print_success "LimitRange 'restrictive-limit-range' removed"
    else
        print_info "No restrictive LimitRange found"
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
    echo "  • kubectl get limitrange -n ${NAMESPACE}"
    echo "  • kubectl describe limitrange restrictive-limit-range -n ${NAMESPACE}"
    echo "  • kubectl get pods -n ${NAMESPACE} -l app=contacts -w"
    echo "  • kubectl describe deployment contacts -n ${NAMESPACE}"
    echo "  • kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' | grep -i limitrange"
    echo ""
    print_warning "contacts deployment should show 0/1 ready with pods failing to create"
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
    echo "  • kubectl get limitrange -n ${NAMESPACE}"
    echo "    (Should NOT show: restrictive-limit-range)"
    echo ""
    echo "  • kubectl get pods -l app=contacts -n ${NAMESPACE}"
    echo "    (contacts pods should be able to restart now)"
    echo ""
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

# Handle command line arguments using common handler
handle_scenario_command "$@"

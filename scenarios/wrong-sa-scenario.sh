#!/bin/bash

# Wrong ServiceAccount Scenario
# This script applies a deployment with a mismatched ServiceAccount name
#
# Usage:
#   ./wrong-sa-scenario.sh          # Inject failure (default)
#   ./wrong-sa-scenario.sh inject   # Inject failure
#   ./wrong-sa-scenario.sh revert    # Revert failure

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="WrongServiceAccount"
SCENARIO_DESCRIPTION="Applies a deployment with a mismatched ServiceAccount name causing pod failures"

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
    echo "  This scenario applies a deployment configuration where the ServiceAccount"
    echo "  name in the pod spec does not match the actual ServiceAccount name."
    echo "  The deployment references 'risk-assessment' but the ServiceAccount is"
    echo "  named 'riskassessment', causing pods to fail to start with ServiceAccount"
    echo "  not found errors."
    echo ""
    echo "Affected Services:"
    echo "  • riskassessment: Deployment uses wrong ServiceAccount name"
    echo "  • Pods fail to start due to ServiceAccount mismatch"
    echo ""
    echo "Expected Behavior:"
    echo "  • ServiceAccount 'riskassessment' is created"
    echo "  • Deployment 'riskassessment' is created with serviceAccountName: 'risk-assessment'"
    echo "  • Pods fail to start with 'ServiceAccount \"risk-assessment\" not found' error"
    echo "  • Deployment shows CrashLoopBackOff or ImagePullBackOff status"
    echo "  • Pods cannot be scheduled due to ServiceAccount validation failure"
    echo ""
    echo "Observable Symptoms:"
    echo "  • kubectl get pods shows pods in Pending or CrashLoopBackOff state"
    echo "  • kubectl describe pod shows 'ServiceAccount \"risk-assessment\" not found'"
    echo "  • kubectl get events shows ServiceAccount not found errors"
    echo "  • Deployment shows 0/1 ready replicas"
    echo "  • ServiceAccount 'riskassessment' exists but deployment references 'risk-assessment'"
    echo ""
    echo "Real-World Scenarios This Represents:"
    echo "  • Typo in ServiceAccount name (hyphen vs no hyphen)"
    echo "  • Copy-paste error in deployment configuration"
    echo "  • ServiceAccount renamed but deployment not updated"
    echo "  • Configuration drift between ServiceAccount and deployment"
    echo "  • RBAC misconfiguration causing pod startup failures"
    echo ""
    echo "=========================================="
    echo ""
}

# ==============================================================================
# INJECT FAILURE
# ==============================================================================

inject_failure() {
    local yaml_file="${SCRIPT_DIR}/wrong-sa-scenario.yaml"
    
    if [ ! -f "$yaml_file" ]; then
        print_error "YAML file not found: ${yaml_file}"
        exit 1
    fi

    print_info "Applying wrong ServiceAccount configuration..."
    
    # Replace namespace in YAML and apply
    sed "s/namespace: anthos-bank/namespace: ${NAMESPACE}/g" "$yaml_file" | \
        kubectl apply -f -
    
    print_success "Wrong ServiceAccount configuration applied"
    sleep 2

    print_info "Checking deployment status..."
    kubectl get deployment riskassessment -n "${NAMESPACE}" -o wide 2>/dev/null || true
    
    echo ""
    print_info "Checking pod status..."
    kubectl get pods -n "${NAMESPACE}" -l app=riskassessment -o wide 2>/dev/null || true
    
    echo ""
    print_warning "Pods should fail to start due to ServiceAccount name mismatch"
}

# ==============================================================================
# REVERT FAILURE
# ==============================================================================

revert_failure() {
    print_info "Removing wrong ServiceAccount configuration..."
    
    local yaml_file="${SCRIPT_DIR}/wrong-sa-scenario.yaml"
    
    if [ ! -f "$yaml_file" ]; then
        print_warning "YAML file not found: ${yaml_file}"
        print_info "Attempting to delete resources manually..."
        
        kubectl delete deployment riskassessment -n "${NAMESPACE}" 2>/dev/null || true
        kubectl delete service riskassessment -n "${NAMESPACE}" 2>/dev/null || true
        kubectl delete serviceaccount riskassessment -n "${NAMESPACE}" 2>/dev/null || true
        
        print_success "Resources removed"
        return
    fi

    # Replace namespace in YAML and delete
    sed "s/namespace: anthos-bank/namespace: ${NAMESPACE}/g" "$yaml_file" | \
        kubectl delete -f - 2>/dev/null || true
    
    print_success "Wrong ServiceAccount configuration removed"
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
    echo "  • kubectl get pods -n ${NAMESPACE} -l app=riskassessment"
    echo "  • kubectl describe pod <riskassessment-pod> -n ${NAMESPACE}"
    echo "  • kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' | grep -i serviceaccount"
    echo "  • kubectl get deployment riskassessment -n ${NAMESPACE}"
    echo "  • kubectl get serviceaccount riskassessment -n ${NAMESPACE}"
    echo ""
    print_warning "Pods should show ServiceAccount not found errors"
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
    echo "  • kubectl get deployment riskassessment -n ${NAMESPACE}"
    echo "    (Should NOT exist)"
    echo ""
    echo "  • kubectl get serviceaccount riskassessment -n ${NAMESPACE}"
    echo "    (Should NOT exist)"
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


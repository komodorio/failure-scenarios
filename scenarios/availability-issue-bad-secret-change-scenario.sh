#!/bin/bash

# Availability Issue Bad Secret Change Scenario
# This script creates a deployment with a validated secret, then breaks it by changing the secret value
#
# Usage:
#   ./availability-issue-bad-secret-change-scenario.sh          # Inject failure (default)
#   ./availability-issue-bad-secret-change-scenario.sh inject   # Inject failure
#   ./availability-issue-bad-secret-change-scenario.sh revert   # Revert failure

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="Availability Issue Bad Secret Change"
SCENARIO_DESCRIPTION="Deploys application with validated secret, then breaks it by changing secret value"

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
    echo "  This scenario demonstrates how secret configuration changes can cause"
    echo "  application availability issues. A Python application validates the"
    echo "  APP_MODE environment variable on startup and only runs when set to 'safe'."
    echo "  After successful deployment, the secret is updated with an invalid value,"
    echo "  and the deployment is restarted, causing pods to fail."
    echo ""
    echo "Affected Services:"
    echo "  • python-worker: Application exits due to invalid APP_MODE value"
    echo ""
    echo "Expected Behavior:"
    echo "  • Initial deployment with APP_MODE=safe succeeds"
    echo "  • Secret is updated to APP_MODE=broken"
    echo "  • Deployment rollout restart is triggered"
    echo "  • New pods fail because application validates APP_MODE on startup"
    echo "  • Pods show CrashLoopBackOff status"
    echo "  • Service becomes unavailable"
    echo ""
    echo "Observable Symptoms:"
    echo "  • Pods in CrashLoopBackOff state"
    echo "  • kubectl logs shows 'Invalid APP_MODE, exiting'"
    echo "  • Exit code 1 in container status"
    echo "  • Back-off restarting failed container"
    echo "  • Deployment shows 0/1 ready replicas"
    echo ""
    echo "Real-World Scenarios This Represents:"
    echo "  • Secret update with invalid configuration value"
    echo "  • Configuration validation failures on startup"
    echo "  • Rolling updates with broken configuration"
    echo "  • Environment variable validation issues"
    echo "  • Availability problems due to config changes"
    echo ""
    echo "=========================================="
    echo ""
}

# ==============================================================================
# INJECT FAILURE
# ==============================================================================

inject_failure() {
    local yaml_file="${SCRIPT_DIR}/availability-issue-bad-secret-change-scenario.yaml"
    
    if [ ! -f "$yaml_file" ]; then
        print_error "YAML file not found: ${yaml_file}"
        exit 1
    fi

    print_info "Deploying application with validated secret..."
    
    # Replace namespace in YAML and apply
    sed "s/namespace: anthos-bank/namespace: ${NAMESPACE}/g" "$yaml_file" | \
        kubectl apply -f -
    
    print_success "Application deployed with valid secret (APP_MODE=safe)"
    sleep 5

    print_info "Waiting for deployment to become ready..."
    kubectl rollout status deployment/python-worker -n "${NAMESPACE}" --timeout=60s 2>/dev/null || true
    
    echo ""
    print_info "Current pod status:"
    kubectl get pods -n "${NAMESPACE}" -l app=python-worker -o wide
    
    echo ""
    print_info "Updating secret with invalid configuration..."
    
    # Delete and recreate the secret with invalid value
    kubectl delete secret app-config -n "${NAMESPACE}" --ignore-not-found=true
    kubectl create secret generic app-config -n "${NAMESPACE}" --from-literal=APP_MODE=broken
    
    print_success "Secret updated to APP_MODE=broken"
    sleep 2
    
    print_info "Triggering rollout restart to pick up new secret..."
    kubectl rollout restart deployment/python-worker -n "${NAMESPACE}"
    
    print_success "Rollout restart triggered"
    sleep 5
    
    echo ""
    print_warning "Pods should now fail with CrashLoopBackOff due to invalid APP_MODE"
    print_info "Checking updated pod status..."
    kubectl get pods -n "${NAMESPACE}" -l app=python-worker -o wide
    
    echo ""
    print_info "Checking pod logs for validation error..."
    local worker_pod
    worker_pod=$(kubectl get pods -n "${NAMESPACE}" -l app=python-worker -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$worker_pod" ]; then
        kubectl logs "$worker_pod" -n "${NAMESPACE}" --tail=20 2>/dev/null || true
    fi
    
    echo ""
    print_info "Checking events for errors..."
    kubectl get events -n "${NAMESPACE}" --sort-by='.lastTimestamp' | grep -i "error\|failed\|back-off" | tail -10 || true
}

# ==============================================================================
# REVERT FAILURE
# ==============================================================================

revert_failure() {
    print_info "Removing availability issue resources..."
    
    local yaml_file="${SCRIPT_DIR}/availability-issue-bad-secret-change-scenario.yaml"
    
    if [ ! -f "$yaml_file" ]; then
        print_warning "YAML file not found: ${yaml_file}"
        print_info "Attempting to delete resources manually..."
        
        kubectl delete deployment python-worker -n "${NAMESPACE}" 2>/dev/null || true
        kubectl delete secret app-config -n "${NAMESPACE}" 2>/dev/null || true
        
        print_success "Resources removed"
        return
    fi

    # Replace namespace in YAML and delete
    sed "s/namespace: anthos-bank/namespace: ${NAMESPACE}/g" "$yaml_file" | \
        kubectl delete -f - 2>/dev/null || true
    
    print_success "Availability issue resources removed"
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
    echo "  • kubectl get pods -n ${NAMESPACE} -l app=python-worker -w"
    echo "  • kubectl logs -f deployment/python-worker -n ${NAMESPACE}"
    echo "  • kubectl describe pod <pod-name> -n ${NAMESPACE}"
    echo "  • kubectl get secret app-config -n ${NAMESPACE} -o yaml"
    echo ""
    print_warning "Pods should show CrashLoopBackOff due to APP_MODE validation failure"
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
    echo "  • kubectl get deployment python-worker -n ${NAMESPACE}"
    echo "    (Should NOT exist)"
    echo ""
    echo "  • kubectl get secret app-config -n ${NAMESPACE}"
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


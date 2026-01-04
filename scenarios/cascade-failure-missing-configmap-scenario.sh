#!/bin/bash

# Cascade Failure Missing ConfigMap Scenario
# This script creates deployments that reference a ConfigMap, then breaks them by changing to non-existent ConfigMap
#
# Usage:
#   ./cascade-failure-missing-configmap-scenario.sh          # Inject failure (default)
#   ./cascade-failure-missing-configmap-scenario.sh inject   # Inject failure
#   ./cascade-failure-missing-configmap-scenario.sh revert   # Revert failure

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="Cascade Failure Missing ConfigMap"
SCENARIO_DESCRIPTION="Deploys multiple services referencing a ConfigMap, then changes to non-existent ConfigMap"

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
    echo "  This scenario deploys multiple web application services that depend on"
    echo "  configuration data stored in ConfigMaps. After successful deployment,"
    echo "  the deployments are updated to reference a ConfigMap that doesn't exist,"
    echo "  causing all pods to fail startup."
    echo ""
    echo "Affected Services:"
    echo "  • web-frontend: Fails to start due to missing ConfigMap reference"
    echo "  • api-backend: Fails to start due to missing ConfigMap reference"
    echo "  • data-processor: Fails to start due to missing ConfigMap reference"
    echo ""
    echo "Expected Behavior:"
    echo "  • Services initially deploy successfully with shared-config ConfigMap"
    echo "  • Deployments are updated to reference fake-config (non-existent)"
    echo "  • All pods remain scheduled but containers fail to start"
    echo "  • Pods show CreateContainerConfigError status"
    echo "  • Rolling update creates new ReplicaSet but pods cannot start"
    echo ""
    echo "Observable Symptoms:"
    echo "  • Pods stuck in CreateContainerConfigError state"
    echo "  • kubectl describe pod shows 'configmap \"fake-config\" not found'"
    echo "  • Deployment shows mismatched replica counts (desired vs ready)"
    echo "  • Events show repeated warnings about missing ConfigMap"
    echo ""
    echo "Real-World Scenarios This Represents:"
    echo "  • ConfigMap renamed but deployment not updated"
    echo "  • Configuration reference typo in deployment manifest"
    echo "  • ConfigMap deleted accidentally while still in use"
    echo "  • Environment drift between dev/staging/prod configurations"
    echo "  • Cascading failures when shared configuration is mismanaged"
    echo ""
    echo "=========================================="
    echo ""
}

# ==============================================================================
# INJECT FAILURE
# ==============================================================================

inject_failure() {
    local yaml_file="${SCRIPT_DIR}/cascade-failure-missing-configmap-scenario.yaml"
    
    if [ ! -f "$yaml_file" ]; then
        print_error "YAML file not found: ${yaml_file}"
        exit 1
    fi

    print_info "Creating shared configuration and services..."
    
    # Replace namespace in YAML and apply
    sed "s/namespace: anthos-bank/namespace: ${NAMESPACE}/g" "$yaml_file" | \
        kubectl apply -f -
    
    print_success "Resources created with working ConfigMap"
    sleep 5

    print_info "Waiting for deployments to become ready..."
    kubectl rollout status deployment/web-frontend -n "${NAMESPACE}" --timeout=60s 2>/dev/null || true
    kubectl rollout status deployment/api-backend -n "${NAMESPACE}" --timeout=60s 2>/dev/null || true
    kubectl rollout status deployment/data-processor -n "${NAMESPACE}" --timeout=60s 2>/dev/null || true
    
    echo ""
    print_info "Current pod status:"
    kubectl get pods -n "${NAMESPACE}" -l scenario=cascade-failure-missing-configmap -o wide
    
    echo ""
    print_info "Updating deployments to reference non-existent ConfigMap..."
    
    # Patch all three deployments to reference fake-config
    for deployment in web-frontend api-backend data-processor; do
        print_info "Patching ${deployment}..."
        kubectl patch deployment "${deployment}" -n "${NAMESPACE}" --type='json' -p='[
            {
                "op": "replace",
                "path": "/spec/template/spec/containers/0/envFrom/0/configMapRef/name",
                "value": "fake-config"
            }
        ]' 2>/dev/null || print_warning "Failed to patch ${deployment}"
    done
    
    print_success "Deployments updated to reference non-existent ConfigMap"
    sleep 5
    
    echo ""
    print_warning "Pods should now fail with CreateContainerConfigError"
    print_info "Checking updated pod status..."
    kubectl get pods -n "${NAMESPACE}" -l scenario=cascade-failure-missing-configmap -o wide
    
    echo ""
    print_info "Checking for ConfigMap errors in events..."
    kubectl get events -n "${NAMESPACE}" --sort-by='.lastTimestamp' | grep -i "configmap\|error" | tail -10 || true
}

# ==============================================================================
# REVERT FAILURE
# ==============================================================================

revert_failure() {
    print_info "Removing cascade failure resources..."
    
    local yaml_file="${SCRIPT_DIR}/cascade-failure-missing-configmap-scenario.yaml"
    
    if [ ! -f "$yaml_file" ]; then
        print_warning "YAML file not found: ${yaml_file}"
        print_info "Attempting to delete resources manually..."
        
        kubectl delete deployment web-frontend -n "${NAMESPACE}" 2>/dev/null || true
        kubectl delete deployment api-backend -n "${NAMESPACE}" 2>/dev/null || true
        kubectl delete deployment data-processor -n "${NAMESPACE}" 2>/dev/null || true
        kubectl delete configmap shared-config -n "${NAMESPACE}" 2>/dev/null || true
        
        print_success "Resources removed"
        return
    fi

    # Replace namespace in YAML and delete
    sed "s/namespace: anthos-bank/namespace: ${NAMESPACE}/g" "$yaml_file" | \
        kubectl delete -f - 2>/dev/null || true
    
    print_success "Cascade failure resources removed"
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
    echo "  • kubectl get pods -n ${NAMESPACE} -l scenario=cascade-failure-missing-configmap -w"
    echo "  • kubectl describe pod <pod-name> -n ${NAMESPACE}"
    echo "  • kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp'"
    echo "  • kubectl get configmap -n ${NAMESPACE}"
    echo ""
    print_warning "Pods should show CreateContainerConfigError due to missing ConfigMap 'fake-config'"
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
    echo "  • kubectl get deployments -n ${NAMESPACE}"
    echo "    (web-frontend, api-backend, data-processor should NOT exist)"
    echo ""
    echo "  • kubectl get configmap shared-config -n ${NAMESPACE}"
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


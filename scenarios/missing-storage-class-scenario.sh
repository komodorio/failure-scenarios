#!/bin/bash

# Failed Job Scenario
# This script applies a StatefulSet with a non-existent StorageClass causing pod failures
#
# Usage:
#   ./failed-job-scenario.sh          # Inject failure (default)
#   ./failed-job-scenario.sh inject   # Inject failure
#   ./failed-job-scenario.sh revert   # Revert failure

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="FailedJob"
SCENARIO_DESCRIPTION="Applies a StatefulSet with a non-existent StorageClass causing persistent volume claim failures"

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
    echo "  This scenario applies a StatefulSet configuration that references a"
    echo "  StorageClass named 'high-iops-rwo' which does not exist in the cluster."
    echo "  The StatefulSet's volumeClaimTemplate fails to create PersistentVolumeClaims,"
    echo "  causing pods to remain in Pending state with volume provisioning errors."
    echo ""
    echo "Affected Services:"
    echo "  • transactions-audit-log: StatefulSet cannot provision volumes"
    echo "  • Pods fail to start due to PVC creation failures"
    echo ""
    echo "Expected Behavior:"
    echo "  • StatefulSet 'transactions-audit-log' is created"
    echo "  • PersistentVolumeClaim creation fails with StorageClass not found"
    echo "  • Pods remain in Pending state"
    echo "  • StatefulSet shows 0/1 ready replicas"
    echo "  • Events show 'StorageClass \"high-iops-rwo\" not found' errors"
    echo ""
    echo "Observable Symptoms:"
    echo "  • kubectl get pods shows pods in Pending state"
    echo "  • kubectl describe pod shows 'waiting for volume to be created'"
    echo "  • kubectl get pvc shows PVCs in Pending state"
    echo "  • kubectl describe pvc shows 'StorageClass \"high-iops-rwo\" not found'"
    echo "  • kubectl get events shows StorageClass not found errors"
    echo "  • StatefulSet shows 0/1 ready replicas"
    echo ""
    echo "Real-World Scenarios This Represents:"
    echo "  • StorageClass misconfiguration or typo"
    echo "  • StorageClass deleted but StatefulSet not updated"
    echo "  • Cluster migration with missing StorageClass definitions"
    echo "  • Multi-cluster deployment with different StorageClass names"
    echo "  • Configuration drift between environments"
    echo "  • Storage backend not properly configured"
    echo ""
    echo "=========================================="
    echo ""
}

# ==============================================================================
# INJECT FAILURE
# ==============================================================================

inject_failure() {
    local yaml_file="${SCRIPT_DIR}/missing-storage-class-scenario.yaml"
    
    if [ ! -f "$yaml_file" ]; then
        print_error "YAML file not found: ${yaml_file}"
        exit 1
    fi

    print_info "Applying StatefulSet with non-existent StorageClass..."
    
    # Replace namespace in YAML and apply
    sed "s/namespace: anthos-bank/namespace: ${NAMESPACE}/g" "$yaml_file" | \
        kubectl apply -f -
    
    print_success "StatefulSet configuration applied"
    sleep 2

    print_info "Checking StatefulSet status..."
    kubectl get statefulset transactions-audit-log -n "${NAMESPACE}" -o wide 2>/dev/null || true
    
    echo ""
    print_info "Checking pod status..."
    kubectl get pods -n "${NAMESPACE}" -l app=transactions-audit-log -o wide 2>/dev/null || true
    
    echo ""
    print_info "Checking PersistentVolumeClaim status..."
    kubectl get pvc -n "${NAMESPACE}" -l app=transactions-audit-log 2>/dev/null || true
    
    echo ""
    print_warning "Pods should fail to start due to StorageClass not found"
}

# ==============================================================================
# REVERT FAILURE
# ==============================================================================

revert_failure() {
    print_info "Removing StatefulSet with non-existent StorageClass..."
    
    local yaml_file="${SCRIPT_DIR}/missing-storage-class-scenario.yaml"
    
    if [ ! -f "$yaml_file" ]; then
        print_warning "YAML file not found: ${yaml_file}"
        print_info "Attempting to delete resources manually..."
        
        kubectl delete statefulset transactions-audit-log -n "${NAMESPACE}" 2>/dev/null || true
        kubectl delete service transactions-audit-log -n "${NAMESPACE}" 2>/dev/null || true
        
        # Delete PVCs created by the StatefulSet
        kubectl delete pvc -n "${NAMESPACE}" -l app=transactions-audit-log 2>/dev/null || true
        
        print_success "Resources removed"
        return
    fi

    # Delete StatefulSet first (this will also delete pods)
    kubectl delete statefulset transactions-audit-log -n "${NAMESPACE}" 2>/dev/null || true
    
    # Delete the service
    sed "s/namespace: anthos-bank/namespace: ${NAMESPACE}/g" "$yaml_file" | \
        grep -A 20 "kind: Service" | \
        sed "s/namespace: anthos-bank/namespace: ${NAMESPACE}/g" | \
        kubectl delete -f - 2>/dev/null || true
    
    # Delete PVCs (they may have been created even if they failed)
    kubectl delete pvc -n "${NAMESPACE}" -l app=transactions-audit-log 2>/dev/null || true
    
    print_success "StatefulSet configuration removed"
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
    echo "  • kubectl get pods -n ${NAMESPACE} -l app=transactions-audit-log"
    echo "  • kubectl describe pod <transactions-audit-log-pod> -n ${NAMESPACE}"
    echo "  • kubectl get pvc -n ${NAMESPACE} -l app=transactions-audit-log"
    echo "  • kubectl describe pvc <pvc-name> -n ${NAMESPACE}"
    echo "  • kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' | grep -i storageclass"
    echo "  • kubectl get statefulset transactions-audit-log -n ${NAMESPACE}"
    echo ""
    print_warning "Pods should show StorageClass not found errors and remain in Pending state"
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
    echo "  • kubectl get statefulset transactions-audit-log -n ${NAMESPACE}"
    echo "    (Should NOT exist)"
    echo ""
    echo "  • kubectl get pvc -n ${NAMESPACE} -l app=transactions-audit-log"
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


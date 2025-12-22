#!/bin/bash

# Node Selector Scenario - Unschedulable Pods
# This script adds a nodeSelector with non-existent labels causing pods to be unschedulable
#
# Usage:
#   ./node-selector-scenario.sh          # Inject failure (default)
#   ./node-selector-scenario.sh inject   # Inject failure
#   ./node-selector-scenario.sh revert   # Revert failure

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="NodeSelector"
SCENARIO_DESCRIPTION="Adds a nodeSelector with non-existent labels causing pods to be unschedulable"

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
    echo "  This scenario adds a nodeSelector constraint to the balancereader deployment"
    echo "  that requires nodes with the label 'workload-type=memory-optimized'. Since no"
    echo "  nodes in the cluster have this label, new pods cannot be scheduled and remain"
    echo "  in Pending state indefinitely. This simulates a common misconfiguration where"
    echo "  nodeSelector requirements don't match available node labels."
    echo ""
    echo "Affected Services:"
    echo "  • balancereader: nodeSelector added with non-existent label requirement"
    echo "  • New pods stuck in Pending state with FailedScheduling events"
    echo ""
    echo "Expected Behavior:"
    echo "  • Deployment triggers rollout with new nodeSelector"
    echo "  • New pod created but cannot be scheduled"
    echo "  • Pod stuck in Pending state"
    echo "  • Scheduler events show: 'no nodes match pod topology spread constraints'"
    echo "  • Old pod(s) may terminate before new pod is ready"
    echo "  • Service becomes unavailable if all pods are pending"
    echo ""
    echo "Observable Symptoms:"
    echo "  • kubectl get pods shows balancereader pod in 'Pending' state"
    echo "  • kubectl describe pod shows: '0/X nodes are available: X node(s) didn't match Pod's node affinity/selector'"
    echo "  • kubectl get events shows: 'FailedScheduling' events"
    echo "  • kubectl get deployment shows unavailable replicas (e.g., READY 0/1)"
    echo "  • Balance checking operations fail in frontend"
    echo "  • No pod restarts (CrashLoopBackOff) - just stuck Pending"
    echo ""
    echo "Real-World Scenarios This Represents:"
    echo "  • Copy-paste error in nodeSelector configuration"
    echo "  • Node labels changed/removed without updating deployments"
    echo "  • Hardware-specific requirements (GPU, high-memory) not available"
    echo "  • Multi-tenant cluster with node pools, wrong pool selected"
    echo "  • Node taints/tolerations misconfiguration"
    echo "  • Kubernetes version upgrade changing node labels"
    echo ""
    echo "=========================================="
    echo ""
}

# ==============================================================================
# INJECT FAILURE
# ==============================================================================

inject_failure() {
    print_info "Adding nodeSelector to balancereader deployment..."

    # Check if balancereader exists
    if ! kubectl get deployment balancereader -n "${NAMESPACE}" >/dev/null 2>&1; then
        print_error "balancereader deployment not found"
        exit 1
    fi

    print_info "Current balancereader pod status:"
    kubectl get pods -l app=balancereader -n "${NAMESPACE}"
    echo ""

    # Add nodeSelector requiring a label that doesn't exist on any node
    print_info "Patching deployment with nodeSelector: workload-type=memory-optimized..."
    kubectl patch deployment balancereader -n "${NAMESPACE}" --type='json' -p='[
        {
            "op": "add",
            "path": "/spec/template/spec/nodeSelector",
            "value": {
                "workload-type": "memory-optimized"
            }
        }
    ]'

    print_success "nodeSelector added successfully"
    print_warning "New pods will be stuck in Pending state (no matching nodes)"

    sleep 3

    print_info "Waiting for deployment rollout to start..."
    sleep 5

    echo ""
    print_info "New pod status:"
    kubectl get pods -l app=balancereader -n "${NAMESPACE}"
}

# ==============================================================================
# REVERT FAILURE
# ==============================================================================

revert_failure() {
    print_info "Removing nodeSelector from balancereader deployment..."

    if ! kubectl get deployment balancereader -n "${NAMESPACE}" >/dev/null 2>&1; then
        print_warning "balancereader deployment not found, skipping"
        return 0
    fi

    # Check if nodeSelector exists
    local node_selector
    node_selector=$(kubectl get deployment balancereader -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.nodeSelector}' 2>/dev/null)

    if [ -n "$node_selector" ] && [ "$node_selector" != "{}" ]; then
        print_info "Found nodeSelector, removing it..."
        kubectl patch deployment balancereader -n "${NAMESPACE}" --type='json' -p='[
            {
                "op": "remove",
                "path": "/spec/template/spec/nodeSelector"
            }
        ]' 2>/dev/null || true
        print_success "nodeSelector removed from balancereader"

        # Wait for rollout
        print_info "Waiting for balancereader to become schedulable..."
        kubectl rollout status deployment/balancereader -n "${NAMESPACE}" --timeout=60s 2>/dev/null || true
    else
        print_info "balancereader has no nodeSelector configured"
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
    print_warning "IMPORTANT: balancereader pod(s) will be stuck in Pending state!"
    echo ""
    print_info "To monitor the effects:"
    echo "  • kubectl get pods -l app=balancereader -n ${NAMESPACE} -w"
    echo "    (Watch pod stuck in Pending state)"
    echo ""
    echo "  • kubectl describe pod -l app=balancereader -n ${NAMESPACE}"
    echo "    (Shows: '0/X nodes are available: node(s) didn't match Pod's node affinity/selector')"
    echo ""
    echo "  • kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' | grep balancereader"
    echo "    (Shows FailedScheduling events)"
    echo ""
    echo "  • kubectl get deployment balancereader -n ${NAMESPACE}"
    echo "    (Shows unavailable replicas)"
    echo ""
    print_info "To see why pods can't be scheduled:"
    echo "  • kubectl describe pod -l app=balancereader -n ${NAMESPACE} | grep -A 10 Events"
    echo ""
    print_info "To check available node labels:"
    echo "  • kubectl get nodes --show-labels"
    echo "  • kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{\"\\t\"}{.metadata.labels}{\"\\n\"}{end}'"
    echo ""
    print_warning "Expected behavior:"
    echo "  • balancereader pod shows as Pending (not Running)"
    echo "  • Events show: 'FailedScheduling: 0/X nodes match nodeSelector'"
    echo "  • Deployment shows: READY 0/1 (unavailable)"
    echo "  • Balance checking operations fail in application"
    echo "  • No nodes have label 'workload-type=memory-optimized'"
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
    echo "  • kubectl get deployment balancereader -n ${NAMESPACE}"
    echo "    (Should not have nodeSelector)"
    echo ""
    echo "  • kubectl get pods -l app=balancereader -n ${NAMESPACE}"
    echo "    (Should show: Running and Ready 1/1)"
    echo ""
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

# Handle command line arguments using common handler
handle_scenario_command "$@"

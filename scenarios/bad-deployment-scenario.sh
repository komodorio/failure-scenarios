#!/bin/bash

# Bad Deployment Scenario
# This script injects a bad deployment with a non-existent image
#
# Usage:
#   ./bad-deployment-scenario.sh          # Inject failure (default)
#   ./bad-deployment-scenario.sh inject   # Inject failure
#   ./bad-deployment-scenario.sh revert   # Revert failure

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="Bad Deployment"
SCENARIO_DESCRIPTION="Updates ledgerwriter to use a non-existent image tag (v999.99.99)"

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
    echo "  This scenario simulates a failed deployment by updating the ledgerwriter"
    echo "  service to use a non-existent image tag (v999.99.99). This represents a common"
    echo "  deployment failure where an invalid image version is accidentally deployed."
    echo ""
    echo "Affected Services:"
    echo "  • ledgerwriter: Image tag changed to v999.99.99 (non-existent)"
    echo ""
    echo "Expected Behavior:"
    echo "  • Kubernetes will create new pods with the invalid image"
    echo "  • Pods will fail to start with ImagePullBackOff status"
    echo "  • Container runtime cannot pull the non-existent image"
    echo "  • Old pods remain running (rollout blocked)"
    echo "  • Deployment rollout stalls"
    echo "  • Service continues using old pods (if RollingUpdate strategy)"
    echo ""
    echo "Observable Symptoms:"
    echo "  • Pod status shows 'ImagePullBackOff' or 'ErrImagePull'"
    echo "  • Deployment shows unavailable replicas"
    echo "  • kubectl rollout status shows deployment stuck"
    echo "  • Events show image pull failures"
    echo "  • Old version continues serving requests"
    echo "  • Deployment marked as 'Progressing' but not completing"
    echo ""
    echo "Real-World Scenarios This Represents:"
    echo "  • Typo in image tag during deployment"
    echo "  • CI/CD pipeline pushes wrong tag"
    echo "  • Image deleted from registry after manifest update"
    echo "  • Wrong registry or repository path"
    echo ""
    echo "=========================================="
    echo ""
}

# ==============================================================================
# INJECT FAILURE
# ==============================================================================

inject_failure() {
    print_info "Injecting bad deployment..."

    kubectl patch deployment ledgerwriter -n "${NAMESPACE}" --type='json' -p='[
        {
            "op": "replace",
            "path": "/spec/template/spec/containers/0/image",
            "value": "us-central1-docker.pkg.dev/bank-of-anthos-ci/bank-of-anthos/ledgerwriter:v999.99.99"
        },
        {
            "op": "replace",
            "path": "/spec/replicas",
            "value": 4
        }
    ]'

    print_success "Bad deployment injected successfully"
    print_info "Deployment is attempting to roll out with invalid image..."
    sleep 2

    kubectl get pods -l app=ledgerwriter -n "${NAMESPACE}"
}

# ==============================================================================
# REVERT FAILURE
# ==============================================================================

revert_failure() {
    print_info "Restoring ledgerwriter image to correct version..."

    if ! kubectl get deployment ledgerwriter -n "${NAMESPACE}" >/dev/null 2>&1; then
        print_warning "ledgerwriter deployment not found, skipping"
        return 0
    fi

    local current_image
    current_image=$(kubectl get deployment ledgerwriter -n "${NAMESPACE}" -o json | \
        jq -r '.spec.template.spec.containers[0].image')

    # Check if image contains v999.99.99 (bad version)
    if [[ "$current_image" == *"v999.99.99"* ]]; then
        print_info "Found bad image version, restoring to correct version..."
        # Use the correct image from the original manifest
        local correct_image="us-central1-docker.pkg.dev/bank-of-anthos-ci/bank-of-anthos/ledgerwriter:v0.6.8@sha256:aa1a38f0a68cb12a724fe27da69e1bf4a25d445a1793b8bb9ae7d17a1be90d17"
        kubectl patch deployment ledgerwriter -n "${NAMESPACE}" --type='json' -p="[
            {
                \"op\": \"replace\",
                \"path\": \"/spec/template/spec/containers/0/image\",
                \"value\": \"${correct_image}\"
            },
            {
                \"op\": \"replace\",
                \"path\": \"/spec/replicas\",
                \"value\": 1
            }
        ]"
        print_success "ledgerwriter image and replicas restored"

        # Wait for rollout
        print_info "Waiting for ledgerwriter to become ready..."
        kubectl rollout status deployment/ledgerwriter -n "${NAMESPACE}" --timeout=60s 2>/dev/null || true
    else
        print_info "ledgerwriter image appears correct (not v999.99.99)"
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
    echo "  • kubectl get pods -n ${NAMESPACE} -l app=ledgerwriter -w"
    echo "  • kubectl describe pod <pod-name> -n ${NAMESPACE}"
    echo "  • kubectl rollout status deployment/ledgerwriter -n ${NAMESPACE}"
    echo "  • kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp'"
    echo ""
    print_warning "New pods should show ImagePullBackOff status soon"
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
    echo "  • kubectl get pods -l app=ledgerwriter -n ${NAMESPACE}"
    echo "    (Should show: Running and Ready)"
    echo ""
    echo "  • kubectl get deployment ledgerwriter -n ${NAMESPACE}"
    echo "    (Should show: correct image version and 1 replica)"
    echo ""
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

# Handle command line arguments using common handler
handle_scenario_command "$@"

#!/bin/bash

# Helm Bad Upgrade Scenario - Invalid Redis Configuration
# This script injects a Helm upgrade failure with a non-existent image tag
#
# Usage:
#   ./helm-bad-upgrade-scenario.sh          # Inject failure (default)
#   ./helm-bad-upgrade-scenario.sh inject   # Inject failure
#   ./helm-bad-upgrade-scenario.sh revert   # Revert failure

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="HelmBadUpgrade"
SCENARIO_DESCRIPTION="Injects a Helm upgrade failure with invalid Redis configuration (--max-memory flag typo)"

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
    echo "  This scenario simulates a failed Helm upgrade by updating the cash-cache"
    echo "  (Redis) chart with a subtle typo in the Redis configuration flag"
    echo "  (--max-memory instead of --maxmemory). The configuration looks correct"
    echo "  but Redis doesn't recognize the flag, causing it to crash on startup."
    echo "  This represents a common deployment failure where configuration errors"
    echo "  are only caught at runtime."
    echo ""
    echo "Affected Services:"
    echo "  • cash-cache (Redis): Invalid flag '--max-memory' causing CrashLoopBackOff"
    echo ""
    echo "Expected Behavior:"
    echo "  • Helm upgrade will succeed (Helm only validates syntax)"
    echo "  • Kubernetes will create new pods with invalid configuration"
    echo "  • Pods will start but Redis will fail immediately"
    echo "  • Containers crash and restart repeatedly"
    echo "  • Pods enter CrashLoopBackOff status"
    echo "  • Deployment rollout stalls"
    echo ""
    echo "Observable Symptoms:"
    echo "  • Pod status shows 'CrashLoopBackOff' or 'Error'"
    echo "  • Container restart count continuously increases"
    echo "  • Deployment shows unavailable replicas"
    echo "  • kubectl get deployment shows READY 0/1"
    echo "  • Pod logs show Redis configuration error"
    echo "  • helm list shows deployment as 'deployed' but not healthy"
    echo ""
    echo "Real-World Scenarios This Represents:"
    echo "  • Invalid configuration values in Helm upgrade"
    echo "  • CI/CD pipeline passes incorrect config parameters"
    echo "  • Configuration validated by Helm but rejected by application"
    echo "  • Syntax correct but semantically invalid settings"
    echo "  • Helm upgrade without runtime validation"
    echo "  • Missing application-level configuration validation"
    echo ""
    echo "=========================================="
    echo ""
}

# Function to check if Helm is installed
check_helm() {
    if ! command -v helm >/dev/null 2>&1; then
        print_error "helm is not installed. Please install helm first."
        exit 1
    fi
}

# Function to check if cash-cache release exists
check_helm_release() {
    if ! helm status cash-cache -n "${NAMESPACE}" >/dev/null 2>&1; then
        print_error "Helm release 'cash-cache' not found in namespace ${NAMESPACE}"
        print_error "Please ensure cash-cache is deployed first"
        exit 1
    fi
    print_success "Found Helm release 'cash-cache'"
}

# ==============================================================================
# INJECT FAILURE
# ==============================================================================

inject_failure() {
    print_info "Injecting bad Helm upgrade..."

    # Show current status
    print_info "Current cash-cache pods:"
    kubectl get pods -l app=cash-cache -n "${NAMESPACE}" || true
    echo ""

    # Perform bad upgrade with invalid Redis configuration
    # Using --max-memory (with hyphen) instead of --maxmemory (no hyphen)
    # This is a subtle typo that looks correct but Redis doesn't recognize it
    print_info "Upgrading cash-cache with subtly invalid Redis configuration..."
    helm upgrade cash-cache "${SCRIPT_DIR}/../bank-of-anthos/helm/redis" \
        -n "${NAMESPACE}" \
        --set 'args[0]=redis-server' \
        --set 'args[1]=--max-memory' \
        --set 'args[2]=100mb' \
        --wait=false

    print_success "Helm upgrade command executed"
    print_info "Deployment is attempting to roll out with invalid configuration..."
    sleep 3

    echo ""
    print_info "New pod status:"
    kubectl get pods -l app=cash-cache -n "${NAMESPACE}"
}

# ==============================================================================
# REVERT FAILURE
# ==============================================================================

revert_failure() {
    print_info "Restoring Helm releases to default values..."

    # Check if helm is installed
    if ! command -v helm >/dev/null 2>&1; then
        print_info "helm not installed, skipping Helm restore"
        return 0
    fi

    # Get the script directory and helm chart path
    local HELM_CHART_PATH="${SCRIPT_DIR}/../bank-of-anthos/helm/redis"

    # Check if cash-cache release exists
    if helm status cash-cache -n "${NAMESPACE}" >/dev/null 2>&1; then
        print_info "Restoring cash-cache Helm release with default values..."
        helm upgrade cash-cache "${HELM_CHART_PATH}" -n "${NAMESPACE}" --reset-values 2>/dev/null || true
        print_success "Helm release 'cash-cache' restored to default values"

        # Wait for Deployment to be ready
        print_info "Waiting for cash-cache Deployment to be ready..."
        kubectl rollout status deployment/cash-cache -n "${NAMESPACE}" --timeout=60s 2>/dev/null || true
    else
        print_info "No Helm release 'cash-cache' found in namespace ${NAMESPACE}"
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
    check_helm
    check_manifests
    check_deployment
    check_helm_release
    create_backup

    # Inject the failure
    echo ""
    inject_failure

    echo ""
    print_success "${SCENARIO_NAME} scenario injected successfully!"
    echo ""
    print_info "To monitor the effects:"
    echo "  • kubectl get pods -n ${NAMESPACE} -l app=cash-cache -w"
    echo "  • kubectl describe pod -n ${NAMESPACE} -l app=cash-cache"
    echo "  • kubectl get deployment -n ${NAMESPACE} cash-cache"
    echo "  • kubectl rollout status deployment/cash-cache -n ${NAMESPACE}"
    echo "  • kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp'"
    echo "  • helm list -n ${NAMESPACE}"
    echo "  • helm history cash-cache -n ${NAMESPACE}"
    echo ""
    print_warning "New pod should show CrashLoopBackOff status soon"
    echo ""
    print_info "To view pod logs:"
    echo "  • kubectl logs -n ${NAMESPACE} -l app=cash-cache --tail=50"
    echo ""
    print_info "To rollback the Helm release:"
    echo "  • helm rollback cash-cache -n ${NAMESPACE}"
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
    echo "  • kubectl get pods -l app=cash-cache -n ${NAMESPACE}"
    echo "    (Should show: Running and Ready 1/1)"
    echo ""
    echo "  • helm list -n ${NAMESPACE}"
    echo "    (Should show: cash-cache as 'deployed')"
    echo ""
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

# Handle command line arguments using common handler
handle_scenario_command "$@"

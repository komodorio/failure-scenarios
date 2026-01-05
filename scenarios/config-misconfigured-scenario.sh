#!/bin/bash

# Config Misconfigured Scenario
# This script injects a configuration error by changing SPRING_DATASOURCE_URL to an invalid key
#
# Usage:
#   ./config-misconfigured-scenario.sh          # Inject failure (default)
#   ./config-misconfigured-scenario.sh inject   # Inject failure
#   ./config-misconfigured-scenario.sh revert   # Revert failure

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="Config Misconfigured"
SCENARIO_DESCRIPTION="Renames SPRING_DATASOURCE_URL to SPRING_DATASOURCE_URL_oops in ConfigMap"

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
    echo "  This scenario simulates a configuration error by renaming the SPRING_DATASOURCE_URL"
    echo "  key in the ledger-db-config ConfigMap to SPRING_DATASOURCE_URL_oops. This breaks"
    echo "  the database connection for ledgerwriter since it expects SPRING_DATASOURCE_URL."
    echo "  The running ledgerwriter pod is then killed to force it to restart with the broken config."
    echo ""
    echo "Affected Services:"
    echo "  • ledgerwriter: Cannot connect to database due to missing SPRING_DATASOURCE_URL"
    echo ""
    echo "Expected Behavior:"
    echo "  • ConfigMap key SPRING_DATASOURCE_URL renamed to SPRING_DATASOURCE_URL_oops"
    echo "  • Running ledgerwriter pod is killed"
    echo "  • New ledgerwriter pod starts but fails to connect to database"
    echo "  • Pod shows connection errors or crash loop"
    echo "  • ledgerwriter service becomes unavailable"
    echo ""
    echo "Observable Symptoms:"
    echo "  • ConfigMap shows SPRING_DATASOURCE_URL_oops instead of SPRING_DATASOURCE_URL"
    echo "  • ledgerwriter pod logs show database connection errors"
    echo "  • Pod may show CrashLoopBackOff or Error status"
    echo "  • Application cannot read database connection string"
    echo "  • ledgerwriter service unavailable"
    echo ""
    echo "Real-World Scenarios This Represents:"
    echo "  • Accidental typo in ConfigMap key name"
    echo "  • Configuration refactoring mistake"
    echo "  • Environment variable name mismatch"
    echo "  • Configuration drift between environments"
    echo ""
    echo "=========================================="
    echo ""
}

# ==============================================================================
# INJECT FAILURE
# ==============================================================================

inject_failure() {
    print_info "Injecting config misconfiguration..."

    # Get the current ConfigMap data
    local current_url
    current_url=$(kubectl get configmap ledger-db-config -n "${NAMESPACE}" -o jsonpath='{.data.SPRING_DATASOURCE_URL}' 2>/dev/null || echo "")
    
    if [ -z "$current_url" ]; then
        print_error "Could not find SPRING_DATASOURCE_URL in ledger-db-config ConfigMap"
        exit 1
    fi

    print_info "Current SPRING_DATASOURCE_URL: ${current_url}"
    print_info "Renaming SPRING_DATASOURCE_URL to SPRING_DATASOURCE_URL_oops..."

    # Patch the ConfigMap to rename the key
    # We need to remove the old key and add the new one
    kubectl patch configmap ledger-db-config -n "${NAMESPACE}" --type='json' -p="[
        {
            \"op\": \"remove\",
            \"path\": \"/data/SPRING_DATASOURCE_URL\"
        },
        {
            \"op\": \"add\",
            \"path\": \"/data/SPRING_DATASOURCE_URL_oops\",
            \"value\": \"${current_url}\"
        }
    ]"

    print_success "ConfigMap updated: SPRING_DATASOURCE_URL renamed to SPRING_DATASOURCE_URL_oops"
    sleep 2

    print_info "Killing running ledgerwriter pod to force restart with broken config..."
    
    # Get all ledgerwriter pods
    local LEDGERWRITER_PODS
    LEDGERWRITER_PODS=$(kubectl get pods -n "${NAMESPACE}" -l app=ledgerwriter -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$LEDGERWRITER_PODS" ]; then
        for pod in $LEDGERWRITER_PODS; do
            print_info "Deleting pod: ${pod}"
            kubectl delete pod "${pod}" -n "${NAMESPACE}" --grace-period=0 --force 2>/dev/null || true
        done
        print_success "ledgerwriter pods deleted"
    else
        print_warning "No ledgerwriter pods found to delete"
    fi

    echo ""
    print_warning "New ledgerwriter pods will fail to start due to missing SPRING_DATASOURCE_URL"
    print_info "Monitoring pod status..."
    sleep 5

    kubectl get pods -n "${NAMESPACE}" -l app=ledgerwriter -o wide
    echo ""
    print_info "Checking ConfigMap status..."
    kubectl get configmap ledger-db-config -n "${NAMESPACE}" -o yaml | grep -A 10 "data:" || true
    echo ""
    print_info "Checking ledgerwriter pod logs for connection errors..."
    local new_pod
    new_pod=$(kubectl get pods -n "${NAMESPACE}" -l app=ledgerwriter -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$new_pod" ]; then
        kubectl logs "${new_pod}" -n "${NAMESPACE}" --tail=20 2>/dev/null || true
    fi
}

# ==============================================================================
# REVERT FAILURE
# ==============================================================================

revert_failure() {
    print_info "Restoring ledger-db-config ConfigMap..."

    if ! kubectl get configmap ledger-db-config -n "${NAMESPACE}" >/dev/null 2>&1; then
        print_warning "ledger-db-config ConfigMap not found, skipping"
        return 0
    fi

    # Check if SPRING_DATASOURCE_URL_oops exists (misconfigured)
    local oops_url
    oops_url=$(kubectl get configmap ledger-db-config -n "${NAMESPACE}" -o jsonpath='{.data.SPRING_DATASOURCE_URL_oops}' 2>/dev/null || echo "")

    if [ -n "$oops_url" ]; then
        print_info "Found misconfigured SPRING_DATASOURCE_URL_oops, restoring to SPRING_DATASOURCE_URL..."
        # Restore the correct key name
        kubectl patch configmap ledger-db-config -n "${NAMESPACE}" --type='json' -p="[
            {
                \"op\": \"remove\",
                \"path\": \"/data/SPRING_DATASOURCE_URL_oops\"
            },
            {
                \"op\": \"add\",
                \"path\": \"/data/SPRING_DATASOURCE_URL\",
                \"value\": \"${oops_url}\"
            }
        ]"
        print_success "ConfigMap restored: SPRING_DATASOURCE_URL_oops renamed back to SPRING_DATASOURCE_URL"

        # Restart ledgerwriter pod to pick up the restored config
        print_info "Restarting ledgerwriter pod to pick up restored config..."
        local LEDGERWRITER_PODS
        LEDGERWRITER_PODS=$(kubectl get pods -n "${NAMESPACE}" -l app=ledgerwriter -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

        if [ -n "$LEDGERWRITER_PODS" ]; then
            for pod in $LEDGERWRITER_PODS; do
                print_info "Deleting pod: ${pod} to restart with correct config"
                kubectl delete pod "${pod}" -n "${NAMESPACE}" --grace-period=0 --force 2>/dev/null || true
            done
            print_success "ledgerwriter pods restarted"
        fi

        # Wait for pod to become ready
        print_info "Waiting for ledgerwriter to become ready..."
        kubectl rollout status deployment/ledgerwriter -n "${NAMESPACE}" --timeout=60s 2>/dev/null || true
    else
        print_info "ledger-db-config ConfigMap appears correct (no SPRING_DATASOURCE_URL_oops found)"
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
    echo "  • kubectl get configmap ledger-db-config -n ${NAMESPACE} -o yaml"
    echo "  • kubectl get pods -n ${NAMESPACE} -l app=ledgerwriter -w"
    echo "  • kubectl logs -f deployment/ledgerwriter -n ${NAMESPACE}"
    echo "  • kubectl describe pod <ledgerwriter-pod> -n ${NAMESPACE}"
    echo ""
    print_warning "ledgerwriter pods should show connection errors due to missing SPRING_DATASOURCE_URL"
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
    echo "  • kubectl get configmap ledger-db-config -n ${NAMESPACE} -o yaml"
    echo "    (Should show: SPRING_DATASOURCE_URL, not SPRING_DATASOURCE_URL_oops)"
    echo ""
    echo "  • kubectl get pods -l app=ledgerwriter -n ${NAMESPACE}"
    echo "    (Should show: Running and Ready)"
    echo ""
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

# Handle command line arguments using common handler
handle_scenario_command "$@"


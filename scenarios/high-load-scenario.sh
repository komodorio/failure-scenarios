#!/bin/bash

# High Load Scenario - CPU Throttling
# This script injects high load by increasing the number of concurrent users
#
# Usage:
#   ./high-load-scenario.sh          # Inject failure (default)
#   ./high-load-scenario.sh inject   # Inject failure
#   ./high-load-scenario.sh revert   # Revert failure

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="HighLoad"
SCENARIO_DESCRIPTION="Increases user load to 200 concurrent users, causing high CPU load and service instability"

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
    echo "  This increases user load to 200 concurrent users, causing high CPU load on the users service."
    echo "  As a result, the frontend becomes unavailable and repeatedly crashes due to backend overload."
    echo ""
    echo "Affected Services:"
    echo "  • loadgenerator: Increased user count to 200"
    echo "  • users service: Experiences high CPU pressure"
    echo "  • frontend: Becomes unavailable and crashes"
    echo ""
    echo "Expected Behavior:"
    echo "  • users service CPU is saturated"
    echo "  • frontend repeatedly restarts and is unreachable"
    echo ""
    echo "=========================================="
    echo ""
}

# ==============================================================================
# INJECT FAILURE
# ==============================================================================

inject_failure() {
    print_info "Injecting high load scenario..."

    # Find the index of the USERS environment variable
    local env_index
    env_index=$(kubectl get deployment loadgenerator -n "${NAMESPACE}" -o json | \
        jq '[.spec.template.spec.containers[0].env[] | .name] | index("USERS")')

    if [ "$env_index" = "null" ] || [ -z "$env_index" ]; then
        print_error "Could not find USERS environment variable in loadgenerator deployment"
        exit 1
    fi

    print_info "Found USERS env variable at index ${env_index}"

    kubectl patch deployment loadgenerator -n "${NAMESPACE}" --type='json' -p="[
        {
            \"op\": \"replace\",
            \"path\": \"/spec/template/spec/containers/0/env/${env_index}/value\",
            \"value\": \"200\"
        }
    ]"

    print_success "High load injected successfully (USERS=200)"
    print_info "Deployment is rolling out with new configuration..."
    sleep 2

    kubectl get pods -l app=loadgenerator -n "${NAMESPACE}"
}

# ==============================================================================
# REVERT FAILURE
# ==============================================================================

revert_failure() {
    print_info "Restoring loadgenerator USERS to default (5)..."

    if ! kubectl get deployment loadgenerator -n "${NAMESPACE}" >/dev/null 2>&1; then
        print_warning "loadgenerator deployment not found, skipping"
        return 0
    fi

    # Find the index of the USERS environment variable
    local env_index
    env_index=$(kubectl get deployment loadgenerator -n "${NAMESPACE}" -o json | \
        jq '[.spec.template.spec.containers[0].env[] | .name] | index("USERS")')

    if [ "$env_index" = "null" ] || [ -z "$env_index" ]; then
        print_warning "USERS env variable not found in loadgenerator, skipping"
        return 0
    fi

    # Get current value
    local current_value
    current_value=$(kubectl get deployment loadgenerator -n "${NAMESPACE}" -o json | \
        jq -r ".spec.template.spec.containers[0].env[${env_index}].value")

    if [ "$current_value" != "5" ]; then
        print_info "Changing USERS from ${current_value} to 5..."
        kubectl patch deployment loadgenerator -n "${NAMESPACE}" --type='json' -p="[
            {
                \"op\": \"replace\",
                \"path\": \"/spec/template/spec/containers/0/env/${env_index}/value\",
                \"value\": \"5\"
            }
        ]" 2>/dev/null || true
        print_success "loadgenerator USERS restored to 5"
    else
        print_info "loadgenerator USERS already at default value (5)"
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
    echo "  • kubectl top pods -n ${NAMESPACE}"
    echo "  • kubectl get pods -n ${NAMESPACE} -w"
    echo "  • Check your monitoring dashboards for CPU metrics"
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
    echo "  • kubectl get deployment loadgenerator -n ${NAMESPACE}"
    echo "    (USERS env should be set to 5)"
    echo ""
    echo "  • kubectl top pods -n ${NAMESPACE}"
    echo "    (CPU usage should return to normal levels)"
    echo ""
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

# Handle command line arguments using common handler
handle_scenario_command "$@"

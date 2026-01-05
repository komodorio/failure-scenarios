#!/bin/bash

# Bank of Anthos - Check All Scenario Namespaces
# This script checks the status of all scenario-specific namespaces

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common helper functions
# shellcheck source=lib/common-helpers.sh
source "${SCRIPT_DIR}/../lib/common-helpers.sh"

# Discover scenarios from filesystem
SCENARIOS=($(discover_scenarios "${SCRIPT_DIR}/.."))

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "  Scenario Namespace Status Check"
    echo "=========================================="
    echo ""

    # Check if scenarios were found
    if [ ${#SCENARIOS[@]} -eq 0 ]; then
        print_error "No scenario files found in ${SCRIPT_DIR}/scenarios/"
        exit 1
    fi

    # Require state to exist
    if ! state_exists; then
        print_error "No state found. Please run ./setup-all-scenarios.sh first."
        exit 1
    fi

    local timestamp
    timestamp=$(get_state_timestamp)
    print_info "Current state timestamp: ${timestamp}"
    echo ""

    local total_namespaces=0
    local ready_namespaces=0
    local not_ready_namespaces=0
    local missing_namespaces=0

    for scenario in "${SCENARIOS[@]}"; do
        namespace=$(get_namespace_with_timestamp "$scenario")
        ((total_namespaces++))

        # Check if namespace exists
        if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
            print_warning "Namespace '${namespace}' does not exist"
            ((missing_namespaces++))
            continue
        fi

        # Check deployment status
        local not_ready=$(kubectl get deployments -l application=bank-of-anthos -n "$namespace" -o json 2>/dev/null | \
            jq -r '.items[] | select(.metadata.name != "ledger-db-backup") | select(.status.readyReplicas != .status.replicas) | .metadata.name' 2>/dev/null | wc -l)

        if [ "$not_ready" -eq 0 ]; then
            print_success "${namespace} - All pods ready"
            ((ready_namespaces++))
        else
            print_warning "${namespace} - ${not_ready} deployment(s) not ready"
            ((not_ready_namespaces++))

            # Show pod status for this namespace
            echo ""
            kubectl get pods -n "$namespace" -l application=bank-of-anthos 2>/dev/null | grep -v "Running.*1/1" || true
            echo ""
        fi
    done

    echo ""
    echo "=========================================="
    echo "  Summary"
    echo "=========================================="
    echo ""
    print_info "Total scenario namespaces: ${total_namespaces}"
    print_success "Ready: ${ready_namespaces}"

    if [ $not_ready_namespaces -gt 0 ]; then
        print_warning "Not ready: ${not_ready_namespaces}"
    fi

    if [ $missing_namespaces -gt 0 ]; then
        print_error "Missing: ${missing_namespaces}"
    fi

    echo ""

    if [ $not_ready_namespaces -eq 0 ] && [ $missing_namespaces -eq 0 ]; then
        print_success "All scenario namespaces are ready!"
    else
        print_info "To wait for a specific namespace to be ready:"
        echo "  kubectl wait --for=condition=available --timeout=300s deployment -l application=bank-of-anthos -n <namespace>"
        echo ""
        print_info "To check pods in a specific namespace:"
        echo "  kubectl get pods -n <namespace>"
    fi

    echo ""
}

# Run main function
main "$@"

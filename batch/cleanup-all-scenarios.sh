#!/bin/bash

# Bank of Anthos - Multi-Scenario Cleanup Script
# This script removes all scenario-specific namespaces

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
    echo "  Cleanup All Scenario Namespaces"
    echo "=========================================="
    echo ""

    # Check if scenarios were found
    if [ ${#SCENARIOS[@]} -eq 0 ]; then
        print_error "No scenario files found in ${SCRIPT_DIR}/scenarios/"
        print_info "Expected files matching pattern: *-scenario.sh"
        exit 1
    fi

    # Require state to exist
    if ! state_exists; then
        print_error "No state found. Please run ./setup-all-scenarios.sh first."
        exit 1
    fi

    # Use state to find namespaces
    local timestamp
    timestamp=$(get_state_timestamp)
    print_info "Current state timestamp: ${timestamp}"
    print_info "Checking for scenario namespaces..."
    echo ""

    existing_namespaces=()
    for scenario in "${SCENARIOS[@]}"; do
        namespace=$(get_namespace_with_timestamp "$scenario")
        if kubectl get namespace "$namespace" >/dev/null 2>&1; then
            existing_namespaces+=("$namespace")
            echo "  • ${namespace}"
        fi
    done

    if [ ${#existing_namespaces[@]} -eq 0 ]; then
        print_info "No scenario namespaces found for current state"
        print_info "Removing state..."
        remove_state
        exit 0
    fi

    echo ""
    print_warning "This will delete ${#existing_namespaces[@]} namespace(s) and all resources within them"
    echo ""
    read -p "Do you want to proceed? (y/n): " -n 1 -r
    echo ""
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Cleanup cancelled"
        exit 0
    fi

    # Delete namespaces in parallel using shared function
    local deletion_success=true
    delete_namespaces_parallel "${existing_namespaces[@]}" || deletion_success=false

    echo ""
    echo "=========================================="
    echo "  Cleanup Summary"
    echo "=========================================="
    echo ""

    # Remove state if cleanup was successful
    if [ "$deletion_success" = true ] && state_exists; then
        print_info "Removing state..."
        remove_state
        print_success "State removed successfully"
    elif [ "$deletion_success" = false ]; then
        print_warning "Some deletions failed. State will not be removed."
    fi

    echo ""
    print_info "Remaining namespaces:"
    kubectl get namespaces | grep -E "NAME|anthos-bank|scenario" || echo "  None"
    echo ""
}

# Run main function
main "$@"

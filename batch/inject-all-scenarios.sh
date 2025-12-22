#!/bin/bash

# Bank of Anthos - Inject All Scenarios
# This script injects all failure scenarios to their respective namespaces in parallel

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
    echo "  Inject All Scenarios"
    echo "=========================================="
    echo ""

    # Check if scenarios were found
    if [ ${#SCENARIOS[@]} -eq 0 ]; then
        print_error "No scenario files found in ${SCRIPT_DIR}/scenarios/"
        exit 1
    fi

    # Check if state exists
    if ! state_exists; then
        print_error "No state found. Please run ./setup-all-scenarios.sh first."
        exit 1
    fi

    local timestamp
    timestamp=$(get_state_timestamp)
    print_info "Current state timestamp: ${timestamp}"
    echo ""

    echo "This script will inject failures in ${#SCENARIOS[@]} namespaces:"
    echo ""

    # Check which namespaces exist
    local existing_namespaces=()
    local missing_namespaces=()

    for scenario in "${SCENARIOS[@]}"; do
        namespace=$(get_namespace_with_timestamp "$scenario")
        if kubectl get namespace "$namespace" >/dev/null 2>&1; then
            existing_namespaces+=("$scenario")
            echo "  ✓ ${namespace}"
        else
            missing_namespaces+=("$scenario")
            echo "  ✗ ${namespace} (missing)"
        fi
    done

    echo ""

    if [ ${#missing_namespaces[@]} -gt 0 ]; then
        print_warning "${#missing_namespaces[@]} namespace(s) do not exist"
        print_info "Run ./setup-all-scenarios.sh first to create all namespaces"
        echo ""
    fi

    if [ ${#existing_namespaces[@]} -eq 0 ]; then
        print_error "No scenario namespaces found. Please run ./setup-all-scenarios.sh first."
        exit 1
    fi

    print_info "Injecting failures in parallel..."
    echo ""

    # Track PIDs for parallel execution
    local pids=()
    local scenario_names=()

    # Launch all scenario injections in background
    for scenario in "${existing_namespaces[@]}"; do
        namespace=$(get_namespace_with_timestamp "$scenario")
        scenario_script="${SCRIPT_DIR}/../scenarios/${scenario}-scenario.sh"

        if [ ! -f "$scenario_script" ]; then
            print_warning "Script not found: ${scenario_script}"
            continue
        fi

        print_info "Starting: ${scenario} → ${namespace}"

        # Run scenario in background with namespace override
        (
            NAMESPACE="$namespace" "$scenario_script" > "/tmp/${scenario}-injection.log" 2>&1
            echo $? > "/tmp/${scenario}-injection.status"
        ) &

        pids+=($!)
        scenario_names+=("$scenario")
    done

    # Wait for all background processes to complete
    echo ""
    print_info "Waiting for all scenarios to complete..."
    echo ""

    local success_count=0
    local fail_count=0

    for i in "${!pids[@]}"; do
        pid="${pids[$i]}"
        scenario="${scenario_names[$i]}"

        # Wait for this specific process
        wait "$pid" 2>/dev/null || true

        # Check exit status
        if [ -f "/tmp/${scenario}-injection.status" ]; then
            status=$(cat "/tmp/${scenario}-injection.status")
            if [ "$status" -eq 0 ]; then
                print_success "${scenario} - injection completed"
                ((success_count++))
            else
                print_error "${scenario} - injection failed (exit code: ${status})"
                print_info "See log: /tmp/${scenario}-injection.log"
                ((fail_count++))
            fi
            rm -f "/tmp/${scenario}-injection.status"
        else
            print_warning "${scenario} - status unknown"
            ((fail_count++))
        fi
    done

    echo ""
    echo "=========================================="
    echo "  Injection Summary"
    echo "=========================================="
    echo ""
    print_success "Successfully injected: ${success_count}"

    if [ $fail_count -gt 0 ]; then
        print_error "Failed: ${fail_count}"
    fi

    echo ""
    print_info "To check status of all namespaces:"
    echo "  ./check-all-scenarios.sh"
    echo ""
    print_info "To view logs for a failed injection:"
    echo "  cat /tmp/<scenario-name>-injection.log"
    echo ""
    print_info "To monitor pods in all namespaces:"
    for scenario in "${existing_namespaces[@]}"; do
        namespace=$(get_namespace_with_timestamp "$scenario")
        echo "  kubectl get pods -n ${namespace}"
    done
    echo ""

    # Cleanup old log files
    print_info "Cleaning up temporary log files..."
    rm -f /tmp/*-injection.log
    echo ""
}

# Run main function
main "$@"

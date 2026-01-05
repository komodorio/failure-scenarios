#!/bin/bash

# Bank of Anthos - Restore All Scenarios
# This script restores all failure scenarios in their respective namespaces in parallel

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
    echo "  Restore All Scenarios"
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

    echo "This script will restore failures in ${#SCENARIOS[@]} namespaces:"
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
        echo ""
    fi

    if [ ${#existing_namespaces[@]} -eq 0 ]; then
        print_error "No scenario namespaces found. Nothing to restore."
        exit 1
    fi

    print_info "Restoring all scenarios in parallel..."
    echo ""

    # Track PIDs for parallel execution
    local pids=()
    local scenario_names=()

    # Launch all scenario restores in background
    for scenario in "${existing_namespaces[@]}"; do
        namespace=$(get_namespace_with_timestamp "$scenario")
        restore_script="${SCRIPT_DIR}/../scenarios/restore.sh"

        if [ ! -f "$restore_script" ]; then
            print_warning "Restore script not found: ${restore_script}"
            continue
        fi

        print_info "Starting restore: ${scenario} → ${namespace}"

        # Run restore in background with namespace override
        (
            NAMESPACE="$namespace" "$restore_script" > "/tmp/${scenario}-restore.log" 2>&1
            echo $? > "/tmp/${scenario}-restore.status"
        ) &

        pids+=($!)
        scenario_names+=("$scenario")
    done

    # Wait for all background processes to complete
    echo ""
    print_info "Waiting for all restores to complete..."
    echo ""

    local success_count=0
    local fail_count=0

    for i in "${!pids[@]}"; do
        pid="${pids[$i]}"
        scenario="${scenario_names[$i]}"

        # Wait for this specific process
        wait "$pid" 2>/dev/null || true

        # Check exit status
        if [ -f "/tmp/${scenario}-restore.status" ]; then
            status=$(cat "/tmp/${scenario}-restore.status")
            if [ "$status" -eq 0 ]; then
                print_success "${scenario} - restore completed"
                ((success_count++))
            else
                print_error "${scenario} - restore failed (exit code: ${status})"
                print_info "See log: /tmp/${scenario}-restore.log"
                ((fail_count++))
            fi
            rm -f "/tmp/${scenario}-restore.status"
        else
            print_warning "${scenario} - status unknown"
            ((fail_count++))
        fi
    done

    echo ""
    echo "=========================================="
    echo "  Restore Summary"
    echo "=========================================="
    echo ""
    print_success "Successfully restored: ${success_count}"

    if [ $fail_count -gt 0 ]; then
        print_error "Failed: ${fail_count}"
    fi

    echo ""
    print_info "To check status of all namespaces:"
    echo "  ./check-all-scenarios.sh"
    echo ""
    print_info "To view logs for a failed restore:"
    echo "  cat /tmp/<scenario-name>-restore.log"
    echo ""
    print_info "To monitor pods in all namespaces:"
    for scenario in "${existing_namespaces[@]}"; do
        namespace=$(get_namespace_with_timestamp "$scenario")
        echo "  kubectl get pods -n ${namespace}"
    done
    echo ""

    # Cleanup old log files on success
    if [ $fail_count -eq 0 ]; then
        print_info "Cleaning up temporary log files..."
        rm -f /tmp/*-restore.log
    fi
    echo ""
}

# Run main function
main "$@"

#!/bin/bash

# Restore to Normal Scenario
# This script restores all services to their normal state by calling revert on all scenarios

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Function to print scenario description
print_scenario_description() {
    echo ""
    echo "=========================================="
    echo "  Restore to Normal State"
    echo "=========================================="
    echo ""
    echo "Description:"
    echo "  This script restores all Bank of Anthos services to their normal,"
    echo "  healthy state by calling the revert action on all discovered scenario"
    echo "  scripts. Each scenario knows how to clean up its own failure conditions."
    echo ""
    echo "Actions Performed:"
    echo "  • Discover all scenario scripts in the scenarios/ directory"
    echo "  • Call 'revert' action on each scenario script"
    echo "  • Each scenario reverts its specific failure condition:"
    echo "    - bad-deployment: Restore correct image and replica count"
    echo "    - config-misconfigured: Fix ConfigMap key naming"
    echo "    - database-lock: Release database table locks"
    echo "    - helm-bad-upgrade: Restore Helm release with default values"
    echo "    - high-load: Reset load generator to 5 users"
    echo "    - limit-range-contacts: Remove restrictive LimitRange"
    echo "    - network-policy: Remove blocking NetworkPolicy"
    echo "    - node-selector: Remove unschedulable nodeSelector"
    echo "    - oom-killed: Restore memory limits and JVM settings"
    echo "    - resource-quota: Remove ResourceQuota and scale down"
    echo "  • Reapply original manifests from backup (if needed)"
    echo "  • Wait for all deployments to become ready"
    echo ""
    echo "Expected Behavior:"
    echo "  • All injected failures are reverted"
    echo "  • Services return to original resource limits"
    echo "  • All pods restart with correct configurations"
    echo "  • System returns to stable, healthy state"
    echo ""
    echo "=========================================="
    echo ""
}

# Function to discover all scenario scripts
discover_scenario_scripts() {
    local scenarios=()

    # Find all *-scenario.sh files except network-policy-scenario.sh (we'll handle it separately)
    for scenario_file in "${SCRIPT_DIR}"/*-scenario.sh; do
        if [ -f "$scenario_file" ]; then
            local filename=$(basename "$scenario_file")
            # Skip if it's restore.sh itself
            if [ "$filename" != "restore.sh" ]; then
                scenarios+=("$scenario_file")
            fi
        fi
    done

    # Sort scenarios alphabetically for consistent execution order
    if [ ${#scenarios[@]} -gt 0 ]; then
        IFS=$'\n' scenarios=($(sort <<<"${scenarios[@]}"))
        unset IFS
    fi

    echo "${scenarios[@]}"
}

# Function to revert all scenarios
revert_all_scenarios() {
    print_info "Discovering scenario scripts..."
    echo ""

    local scenario_scripts=($(discover_scenario_scripts))

    if [ ${#scenario_scripts[@]} -eq 0 ]; then
        print_warning "No scenario scripts found"
        return 0
    fi

    print_success "Found ${#scenario_scripts[@]} scenario script(s)"
    echo ""

    local reverted_count=0
    local failed_count=0

    for scenario_script in "${scenario_scripts[@]}"; do
        local scenario_name=$(basename "$scenario_script" .sh)

        print_info "Reverting scenario: ${scenario_name}..."
        echo ""

        # Call the scenario script with 'revert' action
        # Suppress detailed output but show errors
        if "${scenario_script}" revert 2>&1 | grep -E "(Reverting|Success|Error|Warning|removed|restored|deleted)" || true; then
            reverted_count=$((reverted_count + 1))
            echo ""
        else
            print_warning "Failed to revert ${scenario_name}"
            failed_count=$((failed_count + 1))
            echo ""
        fi
    done

    echo ""
    echo "=========================================="
    print_success "Reverted ${reverted_count} scenario(s)"
    if [ $failed_count -gt 0 ]; then
        print_warning "Failed to revert ${failed_count} scenario(s)"
    fi
    echo "=========================================="
    echo ""
}

# Function to reapply original manifests from backup (optional cleanup)
reapply_manifests_from_backup() {
    print_info "Checking for backup manifests to reapply..."

    if [ -d "${BACKUP_DIR}" ] && [ "$(ls -A ${BACKUP_DIR} 2>/dev/null)" ]; then
        print_info "Found backup directory: ${BACKUP_DIR}"
        echo ""

        local manifest_count=0
        for manifest in "${BACKUP_DIR}"/*.yaml; do
            if [ -f "$manifest" ]; then
                local manifest_name=$(basename "$manifest")
                print_info "Applying ${manifest_name}..."
                if kubectl apply -f "$manifest" -n "${NAMESPACE}" 2>/dev/null; then
                    manifest_count=$((manifest_count + 1))
                else
                    print_warning "Failed to apply ${manifest_name}"
                fi
            fi
        done

        echo ""
        print_success "Reapplied ${manifest_count} manifest(s) from backup"
        echo ""
    else
        print_info "No backup directory found or it's empty, skipping manifest reapplication"
        echo ""
    fi
}

# Function to wait for deployments to stabilize
wait_for_deployments() {
    print_info "Waiting for deployments to stabilize..."
    echo ""

    local TIMEOUT=180
    local ELAPSED=0
    local INTERVAL=5

    while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
        local NOT_READY
        NOT_READY=$(kubectl get deployments -l application=bank-of-anthos -n "${NAMESPACE}" -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.readyReplicas != .status.replicas) | .metadata.name' 2>/dev/null | wc -l)

        if [ "$NOT_READY" -eq 0 ]; then
            print_success "All deployments are ready!"
            break
        fi

        print_info "Waiting for deployments to become ready... ($ELAPSED seconds elapsed)"
        sleep "$INTERVAL"
        ELAPSED=$((ELAPSED + INTERVAL))
    done

    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        print_warning "Timeout reached. Some deployments may still be rolling out."
    fi

    echo ""
}

# Function to show final status
show_final_status() {
    print_info "Current deployment status:"
    kubectl get pods -l application=bank-of-anthos -n "${NAMESPACE}"

    echo ""
    print_success "Restoration complete!"
    echo ""

    print_info "If any pods are still NotReady, check:"
    echo "  • kubectl describe pod <pod-name> -n ${NAMESPACE}"
    echo "  • kubectl logs <pod-name> -n ${NAMESPACE}"
    echo "  • kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp'"
    echo ""
    print_info "You can now inject a different failure scenario or continue normal operations."
    echo ""
}

# Main execution
main() {
    # Print scenario description
    print_scenario_description

    # Prerequisite checks
    check_manifests
    check_deployment

    # Revert all scenarios by calling their revert actions
    revert_all_scenarios

    # Optionally reapply original manifests from backup
    reapply_manifests_from_backup

    # Wait for deployments to stabilize
    wait_for_deployments

    # Show final status
    show_final_status
}

# Run main function
main "$@"

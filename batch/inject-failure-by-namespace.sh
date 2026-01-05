#!/bin/bash

# Bank of Anthos - Namespace-Specific Failure Injection Script
# This script allows you to inject failures into a specific scenario namespace

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common helper functions
# shellcheck source=lib/common-helpers.sh
source "${SCRIPT_DIR}/../lib/common-helpers.sh"

# Discover scenarios from filesystem
SCENARIOS=($(discover_scenarios "${SCRIPT_DIR}/.."))

# Function to display menu
display_menu() {
    echo ""
    echo "=========================================="
    echo "  Failure Injection by Namespace"
    echo "=========================================="
    echo ""
    echo "Select a scenario to inject failure:"
    echo ""

    local index=1
    for scenario in "${SCENARIOS[@]}"; do
        # Convert scenario name to title case for display
        local display_name=$(scenario_to_title_case "$scenario")
        echo "  ${index}) ${display_name}"
        ((index++))
    done

    echo "  ${index}) Exit"
    echo ""
    echo -n "Enter your choice [1-${index}]: "
}

# Function to get namespace
get_namespace() {
    local scenario_name=$1
    echo "" >&2
    echo "Select target namespace for ${scenario_name}:" >&2
    echo "" >&2
    
    local option_num=1
    
    if state_exists; then
        local timestamp
        timestamp=$(get_state_timestamp)
        local state_namespace
        state_namespace=$(get_namespace_with_timestamp "$scenario_name")
        echo "  ${option_num}) Use state namespace (${state_namespace})" >&2
        ((option_num++))
    fi
    
    echo "  ${option_num}) Use scenario-specific namespace (${scenario_name}-scenario)" >&2
    ((option_num++))
    echo "  ${option_num}) Enter custom namespace" >&2
    echo "" >&2
    echo -n "Enter your choice [1-${option_num}]: " >&2

    read -r ns_choice
    echo "" >&2

    local current_option=1
    
    if state_exists; then
        if [ "$ns_choice" -eq "$current_option" ]; then
            get_namespace_with_timestamp "$scenario_name"
            return
        fi
        ((current_option++))
    fi
    
    if [ "$ns_choice" -eq "$current_option" ]; then
        echo "${scenario_name}-scenario"
    elif [ "$ns_choice" -eq $((current_option + 1)) ]; then
        echo "anthos-bank-${USER}"
    elif [ "$ns_choice" -eq $((current_option + 2)) ]; then
        echo -n "Enter custom namespace: " >&2
        read -r custom_ns
        echo "$custom_ns"
    else
        print_error "Invalid choice"
        exit 1
    fi
}

# Main script execution
main() {
    # Check if scenarios were found
    if [ ${#SCENARIOS[@]} -eq 0 ]; then
        print_error "No scenario files found in ${SCRIPT_DIR}/scenarios/"
        exit 1
    fi

    # If argument provided, use it directly
    if [ $# -eq 1 ]; then
        CHOICE=$1
    else
        # Interactive mode
        display_menu
        read -r CHOICE
    fi

    echo ""

    # Calculate exit option number (number of scenarios + 1)
    local exit_option=$((${#SCENARIOS[@]} + 1))

    # Validate choice
    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
        print_error "Invalid choice. Please enter a number."
        exit 1
    fi

    # Check if user chose exit
    if [ "$CHOICE" -eq "$exit_option" ]; then
        print_info "Exiting..."
        exit 0
    fi

    # Validate choice is within range
    if [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "${#SCENARIOS[@]}" ]; then
        print_error "Invalid choice. Please select 1-${exit_option}."
        exit 1
    fi

    # Get scenario name and script from array (choice - 1 for 0-based indexing)
    local scenario_index=$((CHOICE - 1))
    local scenario_name="${SCENARIOS[$scenario_index]}"
    local scenario_script="${scenario_name}-scenario.sh"

    # Get target namespace
    TARGET_NAMESPACE=$(get_namespace "$scenario_name")

    # Verify namespace exists
    if ! kubectl get namespace "$TARGET_NAMESPACE" >/dev/null 2>&1; then
        print_error "Namespace '${TARGET_NAMESPACE}' does not exist"
        print_info "Available namespaces:"
        kubectl get namespaces | grep -E "anthos-bank|scenario" || true
        exit 1
    fi

    print_info "Injecting failure into namespace: ${TARGET_NAMESPACE}"
    echo ""

    # Execute scenario with the specified namespace
    NAMESPACE="$TARGET_NAMESPACE" "${SCRIPT_DIR}/../scenarios/${scenario_script}"
}

# Run main function
main "$@"

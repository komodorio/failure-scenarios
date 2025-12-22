#!/bin/bash

# Bank of Anthos - Failure Scenarios Injection System
# Main entry point providing a unified interface for batch scenario operations

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common helper functions
# shellcheck source=lib/common-helpers.sh
source "${SCRIPT_DIR}/lib/common-helpers.sh"

# Function to display main menu
display_menu() {
    echo ""
    echo "=========================================="
    echo "  Failure Scenarios Scenario Management"
    echo "=========================================="
    echo ""
    echo "Setup & Deployment:"
    echo "  1) Setup All Scenarios         - Deploy Bank of Anthos to all scenario namespaces"
    echo "  2) Check All Scenarios         - Check status of all scenario namespaces"
    echo ""
    echo "Failure Injection:"
    echo "  3) Inject All Scenarios        - Inject failures in all namespaces (parallel)"
    echo "  4) Inject by Namespace         - Inject failure in specific namespace (interactive)"
    echo ""
    echo "Restoration:"
    echo "  5) Restore All Scenarios       - Restore all namespaces to normal state (parallel)"
    echo "  6) Restore by Namespace        - Restore specific namespace (interactive)"
    echo ""
    echo "Cleanup:"
    echo "  7) Cleanup All Scenarios       - Delete all scenario namespaces (parallel)"
    echo ""
    echo "  8) Exit"
    echo ""
    echo -n "Enter your choice [1-8]: "
}

# Function to run a script and wait for user
run_script() {
    local script_path=$1
    local script_name=$(basename "$script_path")

    echo ""
    print_info "Launching: ${script_name}"
    echo ""

    # Run the script
    "$script_path"

    local exit_code=$?

    echo ""
    if [ $exit_code -eq 0 ]; then
        print_success "${script_name} completed successfully"
    else
        print_error "${script_name} failed with exit code ${exit_code}"
    fi

    echo ""
    echo "Press Enter to return to menu..."
    read -r
}

# Main script execution
main() {
    # Check if batch directory exists
    if [ ! -d "${SCRIPT_DIR}/batch" ]; then
        print_error "batch directory not found at ${SCRIPT_DIR}/batch"
        exit 1
    fi

    while true; do
        clear
        display_menu
        read -r choice

        case $choice in
            1)
                run_script "${SCRIPT_DIR}/batch/setup-all-scenarios.sh"
                ;;
            2)
                run_script "${SCRIPT_DIR}/batch/check-all-scenarios.sh"
                ;;
            3)
                run_script "${SCRIPT_DIR}/batch/inject-all-scenarios.sh"
                ;;
            4)
                run_script "${SCRIPT_DIR}/batch/inject-failure-by-namespace.sh"
                ;;
            5)
                run_script "${SCRIPT_DIR}/batch/restore-all-scenarios.sh"
                ;;
            6)
                run_script "${SCRIPT_DIR}/batch/restore-by-namespace.sh"
                ;;
            7)
                run_script "${SCRIPT_DIR}/batch/cleanup-all-scenarios.sh"
                ;;
            8)
                print_info "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid choice. Please select 1-8."
                echo ""
                echo "Press Enter to continue..."
                read -r
                ;;
        esac
    done
}

# Run main function
main "$@"

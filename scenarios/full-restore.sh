#!/bin/bash

# Full Restore Scenario
# This script performs a complete restore by deleting the namespace and re-running the setup script

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
    echo "  Full Restore - Delete & Re-deploy"
    echo "=========================================="
    echo ""
    echo "Description:"
    echo "  This script performs a complete restore by deleting the entire namespace"
    echo "  and re-running the setup script. This is the most thorough restoration"
    echo "  method, ensuring a completely clean state."
    echo ""
    echo "Actions Performed:"
    echo "  • Delete the entire namespace (${NAMESPACE})"
    echo "  • Re-run setup-bank-of-anthos.sh to deploy fresh"
    echo "  • Wait for all services to be ready"
    echo ""
    echo "Expected Behavior:"
    echo "  • All resources in the namespace are deleted"
    echo "  • Fresh deployment of Bank of Anthos"
    echo "  • All services start with default configurations"
    echo "  • System returns to a completely clean, healthy state"
    echo ""
    echo "WARNING: This will delete ALL resources in the namespace!"
    echo "=========================================="
    echo ""
}

# Function to delete namespace
delete_namespace() {
    print_info "Deleting namespace: ${NAMESPACE}..."
    
    if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
        print_warning "Namespace '${NAMESPACE}' does not exist"
        return 0
    fi
    
    # Delete the namespace (this will delete all resources in it)
    if kubectl delete namespace "${NAMESPACE}" --timeout=120s 2>/dev/null; then
        print_success "Namespace '${NAMESPACE}' deleted successfully"
    else
        print_warning "Namespace deletion may still be in progress (finalizers may delay deletion)"
        print_info "Waiting for namespace to be fully deleted..."
        
        # Wait for namespace to be deleted (with timeout)
        local timeout=180
        local elapsed=0
        local interval=5
        
        while [ "$elapsed" -lt "$timeout" ]; do
            if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
                print_success "Namespace fully deleted"
                break
            fi
            
            print_info "Waiting for namespace deletion to complete... (${elapsed}s elapsed)"
            sleep "$interval"
            elapsed=$((elapsed + interval))
        done
        
        if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
            print_error "Timeout waiting for namespace deletion. You may need to manually check and clean up."
            print_info "Check with: kubectl get namespace ${NAMESPACE}"
            exit 1
        fi
    fi
    
    # Give it a moment to ensure cleanup is complete
    sleep 2
}

# Function to run setup script
run_setup_script() {
    print_info "Running setup script to deploy Bank of Anthos..."
    echo ""
    
    local SETUP_SCRIPT="${PROJECT_ROOT}/setup-bank-of-anthos.sh"
    
    if [ ! -f "${SETUP_SCRIPT}" ]; then
        print_error "Setup script not found at: ${SETUP_SCRIPT}"
        exit 1
    fi
    
    # Make sure it's executable
    chmod +x "${SETUP_SCRIPT}"
    
    # Run the setup script
    print_info "Executing: ${SETUP_SCRIPT}"
    echo ""
    
    if bash "${SETUP_SCRIPT}"; then
        print_success "Setup script completed successfully"
    else
        print_error "Setup script failed. Please check the output above for errors."
        exit 1
    fi
}

# Main execution
main() {
    # Print scenario description
    print_scenario_description
    
    # Check if manifests directory exists (needed for setup script)
    check_manifests
    
    # 1. Delete namespace
    delete_namespace
    echo ""
    
    # 2. Run setup script
    run_setup_script
    echo ""
    
    print_success "Full restore complete!"
    print_info "Bank of Anthos has been completely re-deployed in namespace: ${NAMESPACE}"
    echo ""
}

# Run main function
main "$@"


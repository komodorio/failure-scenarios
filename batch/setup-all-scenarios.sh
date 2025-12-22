#!/bin/bash

# Bank of Anthos - Multi-Scenario Setup Script
# This script deploys Bank of Anthos in separate namespaces for each scenario
# Each namespace will be named after the scenario (e.g., "bad-deployment-scenario")

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common helper functions
# shellcheck source=lib/common-helpers.sh
source "${SCRIPT_DIR}/../lib/common-helpers.sh"

# Discover scenarios from filesystem
SCENARIOS=($(discover_scenarios "${SCRIPT_DIR}/.."))

# Function to deploy Bank of Anthos to a specific namespace
deploy_to_namespace() {
    local namespace=$1

    print_info "=========================================="
    print_info "Deploying to namespace: ${namespace}"
    print_info "=========================================="
    echo ""

    # Change to bank-of-anthos directory
    cd "${SCRIPT_DIR}/../bank-of-anthos"

    # Check if namespace exists, create if it doesn't
    if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        print_info "Namespace '${namespace}' does not exist. Creating it..."
        kubectl create namespace "$namespace"
        print_success "Namespace '${namespace}' created successfully"
    else
        print_info "Namespace '${namespace}' already exists"
    fi
    echo ""

    # Check if jwt-secret.yaml exists
    if [ ! -f "./extras/jwt/jwt-secret.yaml" ]; then
        print_error "JWT secret file not found at ./extras/jwt/jwt-secret.yaml"
        return 1
    fi

    # Check if kubernetes-manifests directory exists
    if [ ! -d "./kubernetes-manifests" ]; then
        print_error "kubernetes-manifests directory not found"
        return 1
    fi

    # Apply JWT secret (replace hardcoded namespace with scenario-specific one)
    print_info "Applying JWT secret..."
    sed "s/namespace: anthos-bank/namespace: ${namespace}/" ./extras/jwt/jwt-secret.yaml | \
        kubectl apply -f - 2>/dev/null || true

    # Apply all Kubernetes manifests (replace hardcoded namespace with scenario-specific one)
    print_info "Applying Kubernetes manifests..."
    for manifest in ./kubernetes-manifests/*.yaml; do
        sed "s/namespace: anthos-bank/namespace: ${namespace}/" "$manifest" | \
            kubectl apply -f - 2>/dev/null || true
    done

    print_success "Kubernetes manifests applied successfully"
    echo ""

    # Deploy Redis using Helm only for helm-bad-upgrade-scenario
    if [[ "$namespace" == helm-bad-upgrade-scenario* ]]; then
        print_info "Deploying Redis (cash-cache) using Helm..."
        helm upgrade --install cash-cache ./helm/redis -n "$namespace" --reset-values 2>/dev/null || true
        print_success "Redis (cash-cache) deployed successfully"
        echo ""
    else
        print_info "Skipping Redis Helm deployment for this namespace"
        echo ""
    fi

    print_success "Deployment to ${namespace} complete!"
    print_info "Pods are starting in the background..."
    echo ""
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "  Bank of Anthos - Multi-Scenario Setup"
    echo "=========================================="
    echo ""

    # Check if scenarios were found
    if [ ${#SCENARIOS[@]} -eq 0 ]; then
        print_error "No scenario files found in ${SCRIPT_DIR}/scenarios/"
        print_info "Expected files matching pattern: *-scenario.sh"
        exit 1
    fi

    # Check if state already exists
    local reuse_existing=false
    local timestamp
    
    if state_exists; then
        local existing_timestamp
        existing_timestamp=$(get_state_timestamp)
        print_info "State already exists with timestamp: ${existing_timestamp}"
        print_info "Checking for existing namespaces, please wait..."
        echo ""
        
        # Check which namespaces already exist
        local existing_count=0
        local missing_count=0
        for scenario in "${SCENARIOS[@]}"; do
            local namespace
            namespace=$(get_namespace_with_timestamp "$scenario")
            if kubectl get namespace "$namespace" >/dev/null 2>&1; then
                ((existing_count++))
            else
                ((missing_count++))
            fi
        done
        
        if [ $existing_count -gt 0 ]; then
            print_info "Found ${existing_count} existing namespace(s) and ${missing_count} missing namespace(s)"
            echo ""
            echo "Options:"
            echo "  1) Reuse existing state - Skip existing namespaces, deploy only missing ones"
            echo "  2) Recreate everything - Delete all namespaces and create fresh state"
            echo "  3) Cancel"
            echo ""
            read -p "Enter your choice [1-3]: " -n 1 -r
            echo ""
            echo ""
            
            case $REPLY in
                1)
                    reuse_existing=true
                    timestamp="$existing_timestamp"
                    print_info "Reusing existing state with timestamp: ${timestamp}"
                    ;;
                2)
                    print_info "Removing existing state and namespaces..."
                    echo ""

                    # Collect existing namespaces
                    local namespaces_to_delete=()
                    for scenario in "${SCENARIOS[@]}"; do
                        local namespace
                        namespace=$(get_namespace_with_timestamp "$scenario")
                        if kubectl get namespace "$namespace" >/dev/null 2>&1; then
                            namespaces_to_delete+=("$namespace")
                        fi
                    done

                    # Delete namespaces in parallel using shared function
                    delete_namespaces_parallel "${namespaces_to_delete[@]}"

                    remove_state
                    print_info "Creating new state..."
                    timestamp=$(create_state)
                    print_success "Created new state with timestamp: ${timestamp}"
                    ;;
                3)
                    print_info "Setup cancelled"
                    exit 0
                    ;;
                *)
                    print_error "Invalid choice"
                    exit 1
                    ;;
            esac
        else
            print_info "State exists but no namespaces found. Creating new state..."
            remove_state
            timestamp=$(create_state)
            print_success "Created new state with timestamp: ${timestamp}"
            reuse_existing=false
        fi
    else
        print_info "Creating new state..."
        timestamp=$(create_state)
        print_success "Created new state with timestamp: ${timestamp}"
        reuse_existing=false
    fi

    echo ""
    echo "This script will deploy Bank of Anthos to ${#SCENARIOS[@]} separate namespaces:"
    echo ""

    local namespaces_to_deploy=()
    for scenario in "${SCENARIOS[@]}"; do
        local namespace
        namespace=$(get_namespace_with_timestamp "$scenario")
        if [ "$reuse_existing" = true ] && kubectl get namespace "$namespace" >/dev/null 2>&1; then
            echo "  • ${namespace} (already exists - will skip)"
        else
            echo "  • ${namespace}"
            namespaces_to_deploy+=("$scenario")
        fi
    done

    if [ ${#namespaces_to_deploy[@]} -eq 0 ]; then
        print_info "All namespaces already exist. Nothing to deploy."
        exit 0
    fi

    echo ""
    if [ "$reuse_existing" = true ]; then
        local skipped_count=$((${#SCENARIOS[@]} - ${#namespaces_to_deploy[@]}))
        print_info "Starting parallel deployment to ${#namespaces_to_deploy[@]} namespace(s) (skipping ${skipped_count} existing)..."
    else
        print_info "Starting parallel deployment to ${#namespaces_to_deploy[@]} namespaces..."
    fi
    echo ""

    # Track PIDs for parallel execution
    local pids=()
    local namespace_names=()

    # Launch deployments only for namespaces that need to be created
    for scenario in "${namespaces_to_deploy[@]}"; do
        namespace=$(get_namespace_with_timestamp "$scenario")

        print_info "Starting deployment: ${namespace}"

        # Run deployment in background
        (
            deploy_to_namespace "$namespace" > "/tmp/${namespace}-deployment.log" 2>&1
            echo $? > "/tmp/${namespace}-deployment.status"
            # Call scenario's auto-apply action (scenarios that override it will apply, others do nothing)
            local scenario_script="${SCRIPT_DIR}/../scenarios/${scenario}-scenario.sh"
            if [ -f "$scenario_script" ]; then
                NAMESPACE="$namespace" "$scenario_script" auto-apply > "/tmp/${scenario}-auto-apply.log" 2>&1 || true
            fi
        ) &

        pids+=($!)
        namespace_names+=("$namespace")
    done

    # Wait for all background processes to complete
    echo ""
    print_info "Waiting for all deployments to complete..."
    echo ""

    local success_count=0
    local fail_count=0

    for i in "${!pids[@]}"; do
        pid="${pids[$i]}"
        namespace="${namespace_names[$i]}"

        # Wait for this specific process
        wait "$pid" 2>/dev/null || true

        # Check exit status
        if [ -f "/tmp/${namespace}-deployment.status" ]; then
            status=$(cat "/tmp/${namespace}-deployment.status")
            if [ "$status" -eq 0 ]; then
                print_success "${namespace} - deployment completed"
                ((success_count++))
                
            else
                print_error "${namespace} - deployment failed (exit code: ${status})"
                print_info "See log: /tmp/${namespace}-deployment.log"
                ((fail_count++))
            fi
            rm -f "/tmp/${namespace}-deployment.status"
        else
            print_warning "${namespace} - status unknown"
            ((fail_count++))
        fi
    done

    # Cleanup deployment logs on success
    if [ $fail_count -eq 0 ]; then
        print_info "Cleaning up temporary log files..."
        rm -f /tmp/*-deployment.log
    fi

    echo ""
    echo "=========================================="
    echo "  Deployment Summary"
    echo "=========================================="
    echo ""
    
    if [ "$reuse_existing" = true ]; then
        local skipped_count=$((${#SCENARIOS[@]} - ${#namespaces_to_deploy[@]}))
        if [ $skipped_count -gt 0 ]; then
            print_info "Skipped ${skipped_count} existing namespace(s)"
        fi
    fi
    
    print_success "Successfully deployed to ${success_count} namespaces"

    if [ $fail_count -gt 0 ]; then
        print_error "Failed to deploy to ${fail_count} namespaces"
    fi

    echo ""
    print_info "Pods are starting in the background."
    echo ""
    print_info "To check status of all scenario namespaces:"
    echo "  ./check-all-scenarios.sh"
    echo ""
    print_info "Current state timestamp: ${timestamp}"
    echo ""
    print_info "To check pods in a specific namespace:"
    echo "  kubectl get pods -n <scenario-name>-scenario-${timestamp}"
    echo ""
    print_info "To wait for all deployments to be ready in a namespace:"
    echo "  kubectl wait --for=condition=available --timeout=300s deployment -l application=bank-of-anthos -n <namespace>"
    echo ""
    print_info "To inject failures, use the scenario scripts with NAMESPACE env var:"
    echo "  NAMESPACE=<scenario-name>-scenario-${timestamp} ./scenarios/<scenario-name>-scenario.sh"
    echo ""
}

# Run main function
main "$@"

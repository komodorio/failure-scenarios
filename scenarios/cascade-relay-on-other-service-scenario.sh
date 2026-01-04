#!/bin/bash

# Cascade Relay on Other Service Scenario
# This script creates interdependent microservices, then breaks the server causing client failures
#
# Usage:
#   ./cascade-relay-on-other-service-scenario.sh          # Inject failure (default)
#   ./cascade-relay-on-other-service-scenario.sh inject   # Inject failure
#   ./cascade-relay-on-other-service-scenario.sh revert   # Revert failure

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="Cascade Relay on Other Service"
SCENARIO_DESCRIPTION="Deploys interdependent microservices, then breaks server causing cascading client failures"

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
    echo "  This scenario demonstrates cascading failures in a microservices architecture."
    echo "  A server service provides essential functionality to client services. After"
    echo "  successful deployment, the server's environment variables are modified to"
    echo "  break functionality, causing all dependent client services to fail."
    echo ""
    echo "Affected Services:"
    echo "  • message-server: Environment variable removed, breaking functionality"
    echo "  • message-client: Fails to receive expected responses from server"
    echo ""
    echo "Expected Behavior:"
    echo "  • Server and client services initially deploy successfully"
    echo "  • Client successfully connects to server service"
    echo "  • Server environment is modified to remove critical MESSAGE variable"
    echo "  • Client services begin failing due to broken server responses"
    echo "  • Cascading failure propagates through dependent services"
    echo ""
    echo "Observable Symptoms:"
    echo "  • Client pods show CrashLoopBackOff or connection errors"
    echo "  • Server pods may be running but not functioning properly"
    echo "  • kubectl logs shows connection refused or unexpected response errors"
    echo "  • Service mesh/observability shows degraded service health"
    echo "  • Increased error rates and timeouts"
    echo ""
    echo "Real-World Scenarios This Represents:"
    echo "  • Configuration change breaks service dependencies"
    echo "  • API contract violation between services"
    echo "  • Environment variable misconfiguration"
    echo "  • Deployment change breaks downstream consumers"
    echo "  • Cascading failures in microservice architectures"
    echo ""
    echo "=========================================="
    echo ""
}

# ==============================================================================
# INJECT FAILURE
# ==============================================================================

inject_failure() {
    local yaml_file="${SCRIPT_DIR}/cascade-relay-on-other-service-scenario.yaml"
    
    if [ ! -f "$yaml_file" ]; then
        print_error "YAML file not found: ${yaml_file}"
        exit 1
    fi

    print_info "Deploying interdependent microservices..."
    
    # Replace namespace in YAML and apply
    sed "s/namespace: anthos-bank/namespace: ${NAMESPACE}/g" "$yaml_file" | \
        kubectl apply -f -
    
    print_success "Server and client services deployed"
    sleep 5

    print_info "Waiting for services to become ready..."
    kubectl rollout status deployment/message-server -n "${NAMESPACE}" --timeout=60s 2>/dev/null || true
    kubectl rollout status deployment/message-client -n "${NAMESPACE}" --timeout=60s 2>/dev/null || true
    
    echo ""
    print_info "Current pod status:"
    kubectl get pods -n "${NAMESPACE}" -l scenario=cascade-relay-on-other-service -o wide
    
    echo ""
    print_info "Updating server to break client dependencies..."
    
    # Patch server deployment to remove MESSAGE environment variable
    print_info "Removing MESSAGE environment variable from server..."
    kubectl patch deployment message-server -n "${NAMESPACE}" --type='json' -p='[
        {
            "op": "remove",
            "path": "/spec/template/spec/containers/0/env/1"
        }
    ]' 2>/dev/null || print_warning "Failed to patch message-server"
    
    print_success "Server configuration updated (MESSAGE variable removed)"
    sleep 5
    
    echo ""
    print_warning "Client services should now begin failing due to broken server responses"
    print_info "Checking updated pod status..."
    kubectl get pods -n "${NAMESPACE}" -l scenario=cascade-relay-on-other-service -o wide
    
    echo ""
    print_info "Checking server logs..."
    local server_pod
    server_pod=$(kubectl get pods -n "${NAMESPACE}" -l app=message-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$server_pod" ]; then
        kubectl logs "$server_pod" -n "${NAMESPACE}" --tail=10 2>/dev/null || true
    fi
    
    echo ""
    print_info "Checking client logs..."
    local client_pod
    client_pod=$(kubectl get pods -n "${NAMESPACE}" -l app=message-client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$client_pod" ]; then
        kubectl logs "$client_pod" -n "${NAMESPACE}" --tail=10 2>/dev/null || true
    fi
}

# ==============================================================================
# REVERT FAILURE
# ==============================================================================

revert_failure() {
    print_info "Removing cascade relay resources..."
    
    local yaml_file="${SCRIPT_DIR}/cascade-relay-on-other-service-scenario.yaml"
    
    if [ ! -f "$yaml_file" ]; then
        print_warning "YAML file not found: ${yaml_file}"
        print_info "Attempting to delete resources manually..."
        
        kubectl delete deployment message-server -n "${NAMESPACE}" 2>/dev/null || true
        kubectl delete deployment message-client -n "${NAMESPACE}" 2>/dev/null || true
        kubectl delete service message-server -n "${NAMESPACE}" 2>/dev/null || true
        
        print_success "Resources removed"
        return
    fi

    # Replace namespace in YAML and delete
    sed "s/namespace: anthos-bank/namespace: ${NAMESPACE}/g" "$yaml_file" | \
        kubectl delete -f - 2>/dev/null || true
    
    print_success "Cascade relay resources removed"
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
    echo "  • kubectl get pods -n ${NAMESPACE} -l scenario=cascade-relay-on-other-service -w"
    echo "  • kubectl logs -f deployment/message-server -n ${NAMESPACE}"
    echo "  • kubectl logs -f deployment/message-client -n ${NAMESPACE}"
    echo "  • kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp'"
    echo ""
    print_warning "Client services should fail due to broken server responses"
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
    echo "  • kubectl get deployments -n ${NAMESPACE}"
    echo "    (message-server, message-client should NOT exist)"
    echo ""
    echo "  • kubectl get service message-server -n ${NAMESPACE}"
    echo "    (Should NOT exist)"
    echo ""
}

# ==============================================================================
# AUTO-APPLY
# ==============================================================================

# Override auto-apply to inject the scenario
action_auto_apply() {
    action_inject
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

# Handle command line arguments using common handler
handle_scenario_command "$@"


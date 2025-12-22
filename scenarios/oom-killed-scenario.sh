#!/bin/bash

# OOM Killed Scenario
# This script injects an Out-Of-Memory condition by reducing memory limits
#
# Usage:
#   ./oom-killed-scenario.sh          # Inject failure (default)
#   ./oom-killed-scenario.sh inject   # Inject failure
#   ./oom-killed-scenario.sh revert   # Revert failure

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="OOMKilled"
SCENARIO_DESCRIPTION="Reduces memory limits for transactionhistory to cause Out-Of-Memory kills"

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
    echo "  This scenario reduces the memory limits for the transactionhistory service to"
    echo "  unreasonably low values (128Mi limit, 64Mi request), causing the container"
    echo "  to be OOMKilled (Out Of Memory Killed) when it exceeds the limit."
    echo ""
    echo "Affected Services:"
    echo "  • transactionhistory: Memory limit reduced from ~512Mi to 128Mi"
    echo ""
    echo "Expected Behavior:"
    echo "  • transactionhistory pod will start normally"
    echo "  • Under load, memory usage will exceed the 128Mi limit"
    echo "  • Kubernetes will kill the container (OOMKilled status)"
    echo "  • Pod will restart automatically due to restart policy"
    echo "  • Continuous crash loop (CrashLoopBackOff) may occur"
    echo "  • transactionhistory service becomes unavailable or highly unstable"
    echo ""
    echo "Observable Symptoms:"
    echo "  • Pod status shows 'OOMKilled' reason"
    echo "  • High restart count on transactionhistory pods"
    echo "  • CrashLoopBackOff state"
    echo "  • Memory metrics hitting the 128Mi ceiling"
    echo "  • transactionhistory service unavailable or intermittent"
    echo "  • 502/504 errors from load balancer"
    echo ""
    echo "=========================================="
    echo ""
}

# ==============================================================================
# INJECT FAILURE
# ==============================================================================

inject_failure() {
    print_info "Injecting OOM condition..."

    # Find the index of the JVM_OPTS environment variable
    local env_index
    env_index=$(kubectl get deployment transactionhistory -n "${NAMESPACE}" -o json | \
        jq '[.spec.template.spec.containers[0].env[] | .name] | index("JVM_OPTS")')

    if [ "$env_index" = "null" ] || [ -z "$env_index" ]; then
        print_error "Could not find JVM_OPTS environment variable in transactionhistory deployment"
        exit 1
    fi

    print_info "Found JVM_OPTS env variable at index ${env_index}"

    kubectl patch deployment transactionhistory -n "${NAMESPACE}" --type='json' -p="[
        {
            \"op\": \"replace\",
            \"path\": \"/spec/template/spec/containers/0/resources/limits/memory\",
            \"value\": \"128Mi\"
        },
        {
            \"op\": \"replace\",
            \"path\": \"/spec/template/spec/containers/0/resources/requests/memory\",
            \"value\": \"64Mi\"
        },
        {
            \"op\": \"replace\",
            \"path\": \"/spec/template/spec/containers/0/env/${env_index}/value\",
            \"value\": \"-XX:+UnlockExperimentalVMOptions -XX:+UseCGroupMemoryLimitForHeap -Xms64m -Xmx128m\"
        }
    ]"

    print_success "OOM condition injected successfully"
    print_info "Deployment is rolling out with new configuration..."
    sleep 2

    kubectl get pods -l app=transactionhistory -n "${NAMESPACE}"
}

# ==============================================================================
# REVERT FAILURE
# ==============================================================================

revert_failure() {
    print_info "Restoring transactionhistory memory and JVM settings..."

    if ! kubectl get deployment transactionhistory -n "${NAMESPACE}" >/dev/null 2>&1; then
        print_warning "transactionhistory deployment not found, skipping"
        return 0
    fi

    # Restore memory limits and requests
    local current_memory_limit
    current_memory_limit=$(kubectl get deployment transactionhistory -n "${NAMESPACE}" -o json | \
        jq -r '.spec.template.spec.containers[0].resources.limits.memory // "512Mi"')

    if [ "$current_memory_limit" != "512Mi" ]; then
        print_info "Restoring memory limits to 512Mi (was ${current_memory_limit})..."
        kubectl patch deployment transactionhistory -n "${NAMESPACE}" --type='json' -p='[
            {
                "op": "replace",
                "path": "/spec/template/spec/containers/0/resources/limits/memory",
                "value": "512Mi"
            },
            {
                "op": "replace",
                "path": "/spec/template/spec/containers/0/resources/requests/memory",
                "value": "256Mi"
            }
        ]' 2>/dev/null || true
        print_success "Memory limits restored"
    fi

    # Restore JVM_OPTS
    local env_index
    env_index=$(kubectl get deployment transactionhistory -n "${NAMESPACE}" -o json | \
        jq '[.spec.template.spec.containers[0].env[] | .name] | index("JVM_OPTS")')

    if [ "$env_index" != "null" ] && [ -n "$env_index" ]; then
        local default_jvm_opts="-XX:+UnlockExperimentalVMOptions -XX:+UseCGroupMemoryLimitForHeap -Xms256m -Xmx512m"
        kubectl patch deployment transactionhistory -n "${NAMESPACE}" --type='json' -p="[
            {
                \"op\": \"replace\",
                \"path\": \"/spec/template/spec/containers/0/env/${env_index}/value\",
                \"value\": \"${default_jvm_opts}\"
            }
        ]" 2>/dev/null || true
        print_success "JVM_OPTS restored to default"
    fi
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
    echo "  • kubectl get pods -n ${NAMESPACE} -l app=transactionhistory -w"
    echo "  • kubectl describe pod <transactionhistory-pod> -n ${NAMESPACE}"
    echo "  • kubectl top pods -n ${NAMESPACE} -l app=transactionhistory"
    echo ""
    print_warning "The transactionhistory pod should start crashing soon with OOMKilled status"
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
    echo "  • kubectl get deployment transactionhistory -n ${NAMESPACE}"
    echo "    (Memory limits should be 512Mi)"
    echo ""
    echo "  • kubectl get pods -l app=transactionhistory -n ${NAMESPACE}"
    echo "    (Should show: Running and Ready 1/1)"
    echo ""
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

# Handle command line arguments using common handler
handle_scenario_command "$@"

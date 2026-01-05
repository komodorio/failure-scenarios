#!/bin/bash

# Kyverno Policy Scenario
# This script installs Kyverno and creates a policy that blocks deployments without a 'department' label
#
# Usage:
#   ./kyverno-policy-scenario.sh          # Inject failure (default)
#   ./kyverno-policy-scenario.sh inject   # Inject failure
#   ./kyverno-policy-scenario.sh revert   # Revert failure

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="KyvernoPolicy"
SCENARIO_DESCRIPTION="Installs Kyverno and creates a policy requiring 'department' label, then deploys a service that violates the policy"

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
    echo "  This scenario demonstrates Kubernetes policy enforcement using Kyverno."
    echo "  It installs Kyverno as a policy engine, creates a ClusterPolicy that"
    echo "  requires all deployments to have a 'department' label, then attempts"
    echo "  to deploy a 'transaction-report' service that violates this policy."
    echo ""
    echo "Components Installed:"
    echo "  1. Kyverno - Kubernetes native policy management"
    echo "  2. ClusterPolicy - Requires 'department' label on PODS (enforced ONLY on ${NAMESPACE})"
    echo "  3. transaction-report Deployment - Missing required label in pod template"
    echo ""
    echo "Affected Services:"
    echo "  • transaction-report: Deployment created but pods cannot start"
    echo "  • Policy enforced on Pod creation, not Deployment creation"
    echo ""
    echo "Expected Behavior:"
    echo "  • Kyverno is installed in 'kyverno' namespace"
    echo "  • ClusterPolicy with background: false (no auto-generation for Deployments)"
    echo "  • Policy enforces ONLY on direct Pod creation"
    echo "  • Deployment 'transaction-report' is CREATED successfully"
    echo "  • When Deployment controller tries to create pods, they are BLOCKED"
    echo "  • Error message: 'Pod must have a department label'"
    echo "  • Deployment shows 0/1 ready replicas (pods blocked)"
    echo "  • Service is created successfully"
    echo ""
    echo "Observable Symptoms:"
    echo "  • kubectl get deployment shows transaction-report with 0/1 ready replicas"
    echo "  • kubectl get pods shows NO pods (creation blocked by policy)"
    echo "  • kubectl describe deployment shows ReplicaSet created but no pods"
    echo "  • kubectl get events shows 'Pod must have a department label' errors"
    echo "  • Kyverno logs show policy violation on Pod creation attempts"
    echo "  • kubectl get service shows transaction-report service (allowed)"
    echo "  • kubectl get clusterpolicy shows require-department-label policy"
    echo ""
    echo "Real-World Scenarios This Represents:"
    echo "  • Policy-as-Code enforcement for compliance"
    echo "  • Organizational labeling standards for cost tracking"
    echo "  • Security policies preventing misconfigured resources"
    echo "  • Admission control blocking non-compliant workloads"
    echo "  • Shift-left governance catching issues before deployment"
    echo "  • Required metadata for resource management"
    echo ""
    echo "Resolution Approaches:"
    echo "  1. Add required 'department' label to deployment"
    echo "  2. Modify policy to be less restrictive"
    echo "  3. Add namespace to policy exclusion list"
    echo "  4. Disable policy validation temporarily"
    echo ""
    echo "=========================================="
    echo ""
}

# ==============================================================================
# INJECT FAILURE
# ==============================================================================

inject_failure() {
    local yaml_file="${SCRIPT_DIR}/kyverno-policy-scenario.yaml"

    if [ ! -f "$yaml_file" ]; then
        print_error "YAML file not found: ${yaml_file}"
        exit 1
    fi

    # Step 1: Check if Helm is installed
    if ! command -v helm >/dev/null 2>&1; then
        print_error "Helm is not installed. Please install Helm first."
        exit 1
    fi

    # Step 2: Install Kyverno
    print_info "Step 1/4: Installing Kyverno policy engine..."
    echo ""

    # Add Kyverno Helm repository
    print_info "Adding Kyverno Helm repository..."
    helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true
    helm repo update >/dev/null 2>&1 || true

    # Check if Kyverno is already installed
    if helm list -n kyverno 2>/dev/null | grep -q kyverno; then
        print_warning "Kyverno is already installed in kyverno namespace"
    else
        print_info "Installing Kyverno via Helm..."
        helm install kyverno kyverno/kyverno -n kyverno --create-namespace \
            --set admissionController.replicas=1 \
            --set backgroundController.replicas=1 \
            --set cleanupController.replicas=1 \
            --set reportsController.replicas=1 \
            --wait --timeout=3m 2>&1 | grep -v "^NAME:" || true

        print_success "Kyverno installed successfully"
    fi

    echo ""
    print_info "Waiting for Kyverno to be ready..."
    kubectl wait --for=condition=available --timeout=120s deployment -l app.kubernetes.io/instance=kyverno -n kyverno 2>/dev/null || true

    echo ""
    print_success "Kyverno is ready"
    echo ""

    # Step 3: Apply the ClusterPolicy
    print_info "Step 2/4: Creating ClusterPolicy to require 'department' label..."
    echo ""

    # Extract and apply just the ClusterPolicy with namespace replacement
    sed "s/NAMESPACE_PLACEHOLDER/${NAMESPACE}/g" "$yaml_file" | \
        awk '/apiVersion: kyverno.io\/v1/,/^---$/ {print; if (/^---$/) exit}' | \
        kubectl apply -f - 2>&1 | grep -v "Warning:" || true

    print_success "ClusterPolicy 'require-department-label' created (enforced on namespace: ${NAMESPACE})"
    echo ""

    # Give the policy a moment to be processed
    sleep 2

    print_info "Checking policy status..."
    kubectl get clusterpolicy require-department-label -o wide 2>/dev/null || true
    echo ""

    # Step 4: Apply the Service (this should succeed)
    print_info "Step 3/4: Creating transaction-report Service..."
    echo ""

    sed "s/NAMESPACE_PLACEHOLDER/${NAMESPACE}/g" "$yaml_file" | \
        awk '/^apiVersion: v1$/,/^---$/ {print; if (/^---$/) exit}' | \
        kubectl apply -f - 2>&1 | grep -v "Warning:" || true

    print_success "Service created successfully"
    echo ""

    # Step 5: Apply the Deployment (this WILL succeed, but pods will be blocked)
    print_info "Step 4/4: Creating transaction-report Deployment..."
    print_info "The deployment will be created, but pods will be blocked by the policy"
    echo ""

    # Apply the deployment
    sed "s/NAMESPACE_PLACEHOLDER/${NAMESPACE}/g" "$yaml_file" | \
        awk '/^apiVersion: apps\/v1$/,/^$/ {if (/^$/) exit; print}' | \
        kubectl apply -f - 2>&1 | grep -v "Warning:" || true

    print_success "Deployment created successfully"
    sleep 2

    echo ""
    print_info "Verifying deployment and pod status..."
    kubectl get deployment transaction-report -n "${NAMESPACE}" -o wide 2>/dev/null || true

    echo ""
    print_info "Checking for pods (should be NONE - blocked by policy)..."
    kubectl get pods -n "${NAMESPACE}" -l app=transaction-report 2>/dev/null || true

    echo ""
    print_warning "Deployment exists but has 0/1 ready replicas - pods are blocked by policy"
    echo ""
}

# ==============================================================================
# REVERT FAILURE
# ==============================================================================

revert_failure() {
    print_info "Removing Kyverno policy scenario..."
    echo ""

    # Step 1: Delete the Deployment (if it exists)
    print_info "Removing transaction-report Deployment..."
    kubectl delete deployment transaction-report -n "${NAMESPACE}" 2>/dev/null || true

    # Step 2: Delete the Service
    print_info "Removing transaction-report Service..."
    kubectl delete service transaction-report -n "${NAMESPACE}" 2>/dev/null || true

    # Step 3: Delete the ClusterPolicy
    print_info "Removing ClusterPolicy..."
    kubectl delete clusterpolicy require-department-label 2>/dev/null || true

    # Step 4: Uninstall Kyverno
    print_info "Uninstalling Kyverno..."
    if helm list -n kyverno 2>/dev/null | grep -q kyverno; then
        helm uninstall kyverno -n kyverno 2>/dev/null || true
        print_success "Kyverno uninstalled"
    else
        print_info "Kyverno is not installed"
    fi

    # Step 5: Delete Kyverno namespace
    print_info "Removing kyverno namespace..."
    kubectl delete namespace kyverno 2>/dev/null || true

    echo ""
    print_success "Kyverno policy scenario removed"
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

    # Note: We don't create a backup for this scenario as it installs new components

    # Inject the failure
    echo ""
    inject_failure

    echo ""
    print_success "${SCENARIO_NAME} scenario injected successfully!"
    echo ""
    print_info "To monitor the effects:"
    echo "  • kubectl get clusterpolicy require-department-label"
    echo "  • kubectl describe clusterpolicy require-department-label"
    echo "  • kubectl get deployment transaction-report -n ${NAMESPACE}"
    echo "    (Should EXIST with 0/1 ready replicas)"
    echo ""
    echo "  • kubectl get pods -n ${NAMESPACE} -l app=transaction-report"
    echo "    (Should show NO pods - blocked by policy)"
    echo ""
    echo "  • kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp'"
    echo "    (Should show 'Pod must have a department label' errors)"
    echo ""
    echo "  • kubectl get service transaction-report -n ${NAMESPACE}"
    echo "    (Should exist - services are not subject to this policy)"
    echo ""
    echo "  • kubectl get pods -n kyverno"
    echo "    (Kyverno components running)"
    echo ""
    print_info "To test the policy manually IN THIS NAMESPACE (${NAMESPACE}):"
    echo "  Try creating a pod without 'department' label:"
    echo "    kubectl run test-pod --image=nginx -n ${NAMESPACE}"
    echo "    (Pod creation will be BLOCKED)"
    echo ""
    echo "  Try creating a pod WITH 'department' label:"
    echo "    kubectl run test-pod --image=nginx -n ${NAMESPACE} --labels=department=engineering"
    echo "    (Pod creation will SUCCEED)"
    echo ""
    echo "  Note: Deployments will be created, but their pods will be blocked"
    echo "    kubectl create deployment test --image=nginx -n ${NAMESPACE}"
    echo "    (Deployment created, but 0/1 replicas ready)"
    echo ""
    print_warning "Policy enforces Pod creation ONLY in namespace: ${NAMESPACE}"
    print_info "Deployments can be created, but pods without 'department' label will be blocked"
    print_info "Other namespaces are NOT affected by this policy"
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
    echo "  • kubectl get clusterpolicy require-department-label"
    echo "    (Should NOT exist)"
    echo ""
    echo "  • kubectl get deployment transaction-report -n ${NAMESPACE}"
    echo "    (Should NOT exist)"
    echo ""
    echo "  • kubectl get service transaction-report -n ${NAMESPACE}"
    echo "    (Should NOT exist)"
    echo ""
    echo "  • kubectl get namespace kyverno"
    echo "    (Should NOT exist)"
    echo ""
    echo "  • helm list -n kyverno"
    echo "    (Should show no releases)"
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

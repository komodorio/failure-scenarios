#!/bin/bash

# STRICT mTLS Mismatch Scenario - Service Mesh Authentication Failure
# This script creates a PeerAuthentication policy mismatch where one service enforces
# STRICT mTLS while another expects PERMISSIVE or no mTLS, causing handshake failures
#
# Usage:
#   ./mtls-mismatch-scenario.sh          # Inject failure (default)
#   ./mtls-mismatch-scenario.sh inject   # Inject failure
#   ./mtls-mismatch-scenario.sh revert   # Revert failure

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="STRICT mTLS Mismatch"
SCENARIO_DESCRIPTION="Creates PeerAuthentication policy mismatch causing mTLS handshake failures"
PEER_AUTH_NAME="userservice-strict-mtls"
DESTINATION_RULE_NAME="accounts-db-mtls"

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
    echo "  This scenario simulates a common mTLS misconfiguration in service mesh"
    echo "  environments where STRICT mTLS is enforced on one service (userservice)"
    echo "  but the destination service (accounts-db) doesn't have matching TLS settings."
    echo "  Additionally, a NetworkPolicy blocks the connection to GUARANTEE visible failure."
    echo "  This causes mTLS handshake failures, connection resets, and service-to-service"
    echo "  communication breakdowns - a classic issue during gradual service mesh adoption"
    echo "  or when security policies are applied inconsistently across microservices."
    echo ""
    echo "Affected Services:"
    echo "  • userservice: STRICT mTLS enforced + NetworkPolicy blocks database access"
    echo "  • accounts-db: Database service that userservice needs to connect to"
    echo "  • frontend: User authentication and profile operations fail"
    echo ""
    echo "Expected Behavior:"
    echo "  • NetworkPolicy blocks userservice → accounts-db traffic (GUARANTEED FAILURE)"
    echo "  • PeerAuthentication enforces STRICT mTLS on userservice (if Istio present)"
    echo "  • DestinationRule disables TLS for accounts-db (creates mTLS mismatch)"
    echo "  • userservice readiness probe FAILS (cannot connect to database)"
    echo "  • Pod becomes NotReady (0/1 or 0/2) - VISIBLE FAILURE STATUS"
    echo "  • Pod is removed from service endpoints (no traffic routed)"
    echo "  • Frontend shows 'Service Unavailable' or '503' errors"
    echo "  • Logs show connection refused/timeout errors"
    echo ""
    echo "Observable Symptoms:"
    echo "  • userservice pod: Running but NotReady (0/1 or 0/2) - GUARANTEED"
    echo "  • userservice logs: 'Connection refused', 'Connection timed out'"
    echo "  • Readiness probe failures in pod events (database unreachable)"
    echo "  • NetworkPolicy blocks database connection (visible with kubectl describe)"
    echo "  • 'kubectl get peerauthentication' shows STRICT policy on userservice"
    echo "  • 'kubectl get networkpolicy' shows blocking policy on accounts-db"
    echo "  • 'kubectl get destinationrule' shows TLS DISABLE for accounts-db"
    echo "  • Istio proxy logs (if present): TLS handshake errors"
    echo "  • Service mesh metrics: Dropped connections and timeouts"
    echo ""
    echo "Real-World Scenarios This Represents:"
    echo "  • Gradual mTLS rollout causing partial outages"
    echo "  • Copy-paste error in PeerAuthentication manifests"
    echo "  • Security team enforcing STRICT mTLS without proper coordination"
    echo "  • Service mesh migration gone wrong (some services mTLS, others not)"
    echo "  • DestinationRule and PeerAuthentication policy mismatch"
    echo "  • Different teams managing different services with inconsistent policies"
    echo "  • Missing mTLS certificates or CA trust issues"
    echo "  • Non-Istio services trying to communicate with Istio-enabled services"
    echo "  • Health check probes failing after enabling STRICT mTLS"
    echo ""
    echo "=========================================="
    echo ""
}

# Function to check if Istio is installed
check_istio_installed() {
    print_info "Checking if Istio is installed in the cluster..."

    if ! kubectl get namespace istio-system >/dev/null 2>&1; then
        print_warning "Istio namespace 'istio-system' not found"
        print_warning "This scenario is designed for Istio service mesh"
        print_warning "The scenario will still create the policies, but effects will be limited without Istio"
        echo ""
        print_info "To install Istio, visit: https://istio.io/latest/docs/setup/getting-started/"
        echo ""
        return 1
    fi

    if ! kubectl get deployment istiod -n istio-system >/dev/null 2>&1; then
        print_warning "Istio control plane (istiod) not found"
        print_warning "PeerAuthentication policies require Istio to be installed"
        return 1
    fi

    print_success "Istio is installed (istiod found)"
    return 0
}

# Function to check if namespace has Istio sidecar injection enabled
check_istio_injection() {
    print_info "Checking if namespace '${NAMESPACE}' has Istio sidecar injection enabled..."

    local label=$(kubectl get namespace "${NAMESPACE}" -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null || echo "")

    if [ "$label" != "enabled" ]; then
        print_warning "Namespace '${NAMESPACE}' does not have 'istio-injection=enabled' label"
        print_warning "Istio sidecars may not be injected into pods"
        print_info "To enable, run: kubectl label namespace ${NAMESPACE} istio-injection=enabled"
        echo ""
        print_info "Note: Existing pods need to be restarted after labeling the namespace"
        echo ""
        return 1
    fi

    print_success "Istio injection is enabled on namespace '${NAMESPACE}'"
    return 0
}

# Function to check if userservice has Istio sidecar
check_sidecar_present() {
    print_info "Checking if userservice has Istio sidecar proxy..."

    local container_count=$(kubectl get pods -n "${NAMESPACE}" -l app=userservice -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null | wc -w || echo "0")

    if [ "$container_count" -lt 2 ]; then
        print_warning "userservice pod does not appear to have Istio sidecar (found ${container_count} container(s))"
        print_warning "Expected at least 2 containers: application + istio-proxy"
        print_info "The mTLS scenario requires Istio sidecar to be present"
        echo ""
        return 1
    fi

    # Check for istio-proxy container specifically
    if ! kubectl get pods -n "${NAMESPACE}" -l app=userservice -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null | grep -q "istio-proxy"; then
        print_warning "istio-proxy container not found in userservice pod"
        return 1
    fi

    print_success "userservice has Istio sidecar proxy (${container_count} containers)"
    return 0
}

# ==============================================================================
# INJECT FAILURE
# ==============================================================================

inject_failure() {
    local istio_installed=0
    
    # Check if Istio CRDs are available
    if kubectl get crd peerauthentications.security.istio.io >/dev/null 2>&1; then
        istio_installed=1
        print_info "Step 1/3: Creating STRICT mTLS PeerAuthentication policy for userservice..."

        # Create PeerAuthentication policy enforcing STRICT mTLS on userservice
        # This will require all clients connecting to userservice to use mTLS
        kubectl apply -n "${NAMESPACE}" -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: ${PEER_AUTH_NAME}
  namespace: ${NAMESPACE}
spec:
  selector:
    matchLabels:
      app: userservice
  mtls:
    mode: STRICT
EOF

        print_success "PeerAuthentication policy created with STRICT mTLS"
        sleep 1
    else
        print_warning "Step 1/3: Skipping PeerAuthentication (Istio CRDs not installed)"
    fi

    # Check if Istio DestinationRule CRDs are available
    if kubectl get crd destinationrules.networking.istio.io >/dev/null 2>&1; then
        print_info "Step 2/3: Creating mismatched DestinationRule for accounts-db (DISABLE mode)..."

        # Create DestinationRule that disables TLS for accounts-db
        # This creates the mismatch: userservice expects STRICT mTLS, but connects to accounts-db without TLS
        kubectl apply -n "${NAMESPACE}" -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: ${DESTINATION_RULE_NAME}
  namespace: ${NAMESPACE}
spec:
  host: accounts-db.${NAMESPACE}.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
EOF

        print_success "DestinationRule created (TLS disabled for accounts-db)"
        sleep 1
    else
        print_warning "Step 2/3: Skipping DestinationRule (Istio CRDs not installed)"
    fi

    print_info "Step 3/3: Creating NetworkPolicy to block userservice → accounts-db traffic..."
    if [ $istio_installed -eq 0 ]; then
        print_warning "Istio not present - NetworkPolicy will be the primary failure mechanism!"
    else
        print_warning "This NetworkPolicy ensures the failure is visible (combined with mTLS mismatch)!"
    fi

    # Create a NetworkPolicy that blocks userservice from accessing accounts-db
    # This ensures the failure happens regardless of Istio installation
    kubectl apply -n "${NAMESPACE}" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: mtls-mismatch-network-block
  namespace: ${NAMESPACE}
  labels:
    scenario: mtls-mismatch
spec:
  # Apply to accounts-db pods
  podSelector:
    matchLabels:
      app: accounts-db
  policyTypes:
    - Ingress
  ingress:
    # Allow contacts to still access accounts-db (for contrast)
    - from:
      - podSelector:
          matchLabels:
            app: contacts
      ports:
      - protocol: TCP
        port: 5432
    # Allow ledgerwriter (so other services work)
    - from:
      - podSelector:
          matchLabels:
            app: ledgerwriter
      ports:
      - protocol: TCP
        port: 5432
    # Allow balancereader (so other services work)
    - from:
      - podSelector:
          matchLabels:
            app: balancereader
      ports:
      - protocol: TCP
        port: 5432
    # Explicitly BLOCK userservice by not including it
    # (implicit deny-all for any pod not matching the above rules)
EOF

    print_success "NetworkPolicy created - userservice is now blocked from accounts-db"
    print_warning "userservice will fail to connect to the database!"

    sleep 2

    print_info "Restarting userservice to trigger connection failures..."
    kubectl rollout restart deployment/userservice -n "${NAMESPACE}" >/dev/null 2>&1 || true

    sleep 3

    print_info "Policies created:"
    echo ""
    
    if [ $istio_installed -eq 1 ]; then
        kubectl get peerauthentication "${PEER_AUTH_NAME}" -n "${NAMESPACE}" -o wide 2>/dev/null || true
        kubectl get destinationrule "${DESTINATION_RULE_NAME}" -n "${NAMESPACE}" -o wide 2>/dev/null || true
    fi
    
    kubectl get networkpolicy mtls-mismatch-network-block -n "${NAMESPACE}" -o wide 2>/dev/null || true
}

# ==============================================================================
# REVERT FAILURE
# ==============================================================================

revert_failure() {
    local istio_present=0
    
    # Check if Istio resources exist
    if kubectl get peerauthentication "${PEER_AUTH_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
        istio_present=1
    fi
    
    if [ $istio_present -eq 1 ]; then
        print_info "Step 1/3: Removing STRICT mTLS PeerAuthentication policy..."
        kubectl delete peerauthentication "${PEER_AUTH_NAME}" -n "${NAMESPACE}" 2>/dev/null || true
        print_success "PeerAuthentication policy '${PEER_AUTH_NAME}' removed"
    else
        print_info "Step 1/3: Skipping PeerAuthentication removal (not found or Istio not installed)"
    fi

    if kubectl get destinationrule "${DESTINATION_RULE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
        print_info "Step 2/3: Removing mismatched DestinationRule..."
        kubectl delete destinationrule "${DESTINATION_RULE_NAME}" -n "${NAMESPACE}" 2>/dev/null || true
        print_success "DestinationRule '${DESTINATION_RULE_NAME}' removed"
    else
        print_info "Step 2/3: Skipping DestinationRule removal (not found or Istio not installed)"
    fi

    print_info "Step 3/3: Removing NetworkPolicy that blocks userservice..."

    if kubectl get networkpolicy mtls-mismatch-network-block -n "${NAMESPACE}" >/dev/null 2>&1; then
        kubectl delete networkpolicy mtls-mismatch-network-block -n "${NAMESPACE}"
        print_success "NetworkPolicy 'mtls-mismatch-network-block' removed"
    else
        print_info "NetworkPolicy 'mtls-mismatch-network-block' not found (already removed or never created)"
    fi

    print_info "Restarting userservice to restore connectivity..."
    kubectl rollout restart deployment/userservice -n "${NAMESPACE}" >/dev/null 2>&1 || true

    # Wait for userservice to become Ready again
    print_info "Waiting for userservice to become Ready..."
    local timeout=90
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        local ready_pods=$(kubectl get pods -n "${NAMESPACE}" -l app=userservice -o jsonpath='{.items[*].status.containerStatuses[*].ready}' 2>/dev/null | grep -o "true" | wc -l || echo "0")
        local total_containers=$(kubectl get pods -n "${NAMESPACE}" -l app=userservice -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null | wc -w || echo "0")

        if [ "$ready_pods" -ge "$total_containers" ] && [ "$total_containers" -gt 0 ]; then
            print_success "userservice pod is now Ready (${ready_pods}/${total_containers})"
            break
        fi

        sleep 3
        elapsed=$((elapsed + 3))
    done

    if [ $elapsed -ge $timeout ]; then
        print_warning "Timeout waiting for userservice to become Ready"
        print_info "Check pod status with: kubectl get pods -l app=userservice -n ${NAMESPACE}"
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

    echo ""
    
    # Check Istio installation (warnings only, don't fail)
    local istio_installed=0
    check_istio_installed && istio_installed=1
    echo ""

    if [ $istio_installed -eq 1 ]; then
        check_istio_injection
        echo ""
        check_sidecar_present
        echo ""
    fi

    print_warning "Proceeding with mTLS scenario injection..."
    print_info "Note: Maximum effect requires Istio service mesh with sidecar injection"
    echo ""

    # Inject the failure
    inject_failure

    echo ""
    print_success "STRICT mTLS Mismatch scenario injected successfully!"
    echo ""
    print_warning "IMPORTANT: userservice WILL FAIL - This is guaranteed!"
    echo ""
    print_info "Three layers of failure have been created:"
    print_info "  1. NetworkPolicy blocks userservice → accounts-db (L3/L4 layer)"
    print_info "  2. PeerAuthentication enforces STRICT mTLS (L7 layer, if Istio present)"
    print_info "  3. DestinationRule disables TLS (creates policy mismatch)"
    echo ""
    print_warning "Expected result: userservice pod will become NotReady (0/1 or 0/2)"
    print_info "This usually takes 30-60 seconds as readiness probes fail"
    echo ""
    print_info "To monitor the effects:"
    echo "  • kubectl get pods -l app=userservice -n ${NAMESPACE} -w"
    echo "    (Watch for NotReady status if readiness probes fail)"
    echo ""
    echo "  • kubectl logs -f deployment/userservice -n ${NAMESPACE} -c userservice"
    echo "    (Application logs - database connection errors)"
    echo ""
    echo "  • kubectl logs -f deployment/userservice -n ${NAMESPACE} -c istio-proxy"
    echo "    (Istio sidecar logs - TLS handshake failures)"
    echo ""
    echo "  • kubectl describe pod -l app=userservice -n ${NAMESPACE}"
    echo "    (Pod events showing probe failures)"
    echo ""
    echo "  • kubectl get peerauthentication -n ${NAMESPACE}"
    echo "  • kubectl get destinationrule -n ${NAMESPACE}"
    echo ""
    
    if [ $istio_installed -eq 1 ]; then
        echo "  • istioctl x describe pod -l app=userservice -n ${NAMESPACE}"
        echo "    (Detailed Istio configuration and policy analysis)"
        echo ""
        echo "  • istioctl proxy-config cluster -n ${NAMESPACE} <userservice-pod>"
        echo "    (Check mTLS enforcement on clusters)"
        echo ""
    fi

    print_warning "Expected symptoms:"
    echo "  • userservice logs: 'Connection refused', 'TLS handshake timeout'"
    echo "  • Istio proxy logs: 'upstream connect error', 'TLS error'"
    echo "  • Readiness probe may fail if it uses non-mTLS connection"
    echo "  • Pod status: Running but potentially NotReady (0/1 or 0/2)"
    echo "  • Frontend: 503 Service Unavailable for user operations"
    echo "  • Service mesh telemetry: Increased connection failures and timeouts"
    echo ""
    print_info "To investigate (debugging commands):"
    echo "  • kubectl get peerauthentication ${PEER_AUTH_NAME} -n ${NAMESPACE} -o yaml"
    echo "  • kubectl get destinationrule ${DESTINATION_RULE_NAME} -n ${NAMESPACE} -o yaml"
    echo ""
    
    if [ $istio_installed -eq 1 ]; then
        echo "  • istioctl analyze -n ${NAMESPACE}"
        echo "    (Analyze Istio configuration for issues)"
        echo ""
    fi

    print_info "Real-world investigation path:"
    echo "  1. User reports: 'Login not working, 503 errors'"
    echo "  2. Check pod status: 'kubectl get pods -n ${NAMESPACE}'"
    echo "  3. Check logs: Connection/TLS errors in userservice logs"
    echo "  4. Check Istio policies: 'kubectl get peerauthentication,destinationrule -n ${NAMESPACE}'"
    echo "  5. Discover mismatch: STRICT mTLS required but TLS disabled on destination"
    echo "  6. Resolution: Align mTLS policies (remove STRICT or enable TLS)"
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
    echo "  • kubectl get pods -l app=userservice -n ${NAMESPACE}"
    echo "    (Should show: Running and Ready)"
    echo ""
    echo "  • kubectl get peerauthentication -n ${NAMESPACE}"
    echo "    (Should NOT show: ${PEER_AUTH_NAME})"
    echo ""
    echo "  • kubectl get destinationrule -n ${NAMESPACE}"
    echo "    (Should NOT show: ${DESTINATION_RULE_NAME})"
    echo ""
    echo "  • kubectl logs deployment/userservice -n ${NAMESPACE} --tail=20"
    echo "    (Should show normal operation, no TLS errors)"
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

#!/bin/bash

# Memory Intensive CronJob Scenario
# This script deploys a CronJob that repeatedly triggers memory limit exceeded condition
#
# Usage:
#   ./increase-memory-scenario.sh          # Deploy and trigger failure (default)
#   ./increase-memory-scenario.sh inject   # Deploy and trigger failure
#   ./increase-memory-scenario.sh revert   # Clean up resources

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="Memory Intensive CronJob"
SCENARIO_DESCRIPTION="Deploys a CronJob that repeatedly allocates more memory than its limit, triggering container termination every minute"

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
    echo "  This scenario deploys a standalone CronJob (not part of Bank of Anthos) that"
    echo "  simulates a service fetching data from dependencies, then allocates more"
    echo "  memory than its configured limit, causing Kubernetes to terminate the container."
    echo ""
    echo "Resources Deployed:"
    echo "  • Secret: memory-test-script (contains the bash script)"
    echo "  • CronJob: memory-intensive-cronjob (python:3.9-alpine container with 64Mi limit)"
    echo ""
    echo "Expected Behavior:"
    echo "  • CronJob creates pods every 3 minutes"
    echo "  • Each pod prints messages about fetching from dependent services"
    echo "  • Each pod attempts to allocate ~150Mi of memory"
    echo "  • Container exceeds 64Mi limit and gets terminated by Kubernetes"
    echo "  • Repeated failures demonstrate continuous failure pattern"
    echo ""
    echo "Observable Symptoms:"
    echo "  • Pod status shows 'Error' with reason related to memory"
    echo "  • Job shows 0/1 completions with failures"
    echo "  • Container exit code 137 (killed by system)"
    echo "  • Memory usage hitting the 64Mi ceiling before termination"
    echo ""
    echo "=========================================="
    echo ""
}

# ==============================================================================
# INJECT FAILURE (DEPLOY RESOURCES)
# ==============================================================================

inject_failure() {
    print_info "Deploying memory test resources to namespace: ${NAMESPACE}..."

    # Create namespace if it doesn't exist
    if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
        print_info "Creating namespace: ${NAMESPACE}"
        kubectl create namespace "${NAMESPACE}"
    fi

    # Create the bash script as a Secret
    print_info "Creating Secret with memory test script..."
    
    # Create the script content
    cat <<'EOF' | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: v1
kind: Secret
metadata:
  name: memory-test-script
type: Opaque
stringData:
  run.sh: |
    #!/bin/sh
    echo "=========================================="
    echo "Starting memory test service..."
    echo "=========================================="
    echo ""
    echo "[$(date)] Initializing service dependencies..."
    echo "[$(date)] Fetching configuration from authentication service..."
    sleep 1
    echo "[$(date)] Connecting to database service for user data..."
    sleep 1
    echo "[$(date)] Loading cache from redis service..."
    sleep 1
    echo "[$(date)] Retrieving transaction history from ledger service..."
    sleep 1
    echo ""
    echo "[$(date)] All dependencies loaded successfully"
    echo "[$(date)] Allocating memory for data processing..."
    echo ""
    echo "[$(date)] Loading 150MB dataset into memory..."
    python3 /scripts/allocate.py
  allocate.py: |
    import time
    print("[allocator] Allocating memory array...", flush=True)
    # Allocate a large bytearray to consume memory - 150MB to exceed the 64Mi limit
    data = bytearray(150 * 1024 * 1024)  # 150MB
    print("[allocator] Memory allocated successfully - 150MB", flush=True)
    print("[allocator] Service ready to process requests...", flush=True)
    # Keep it in memory
    time.sleep(3600)
EOF

    print_success "Secret created successfully"

    # Create the CronJob that will trigger memory limit exceeded
    print_info "Creating CronJob with memory limit (64Mi) lower than allocation (150Mi)..."
    
    cat <<EOF | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: memory-intensive-cronjob
  labels:
    app: memory-intensive
    scenario: memory-intensive
spec:
  schedule: "*/3 * * * *"  # Every 3 minutes
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 0  # Don't retry on failure
      template:
        metadata:
          labels:
            app: memory-intensive
        spec:
          restartPolicy: Never
          containers:
          - name: memory-test
            image: python:3.9-alpine
            command: ["/bin/sh", "/scripts/run.sh"]
            resources:
              requests:
                memory: "32Mi"
                cpu: "50m"
              limits:
                memory: "64Mi"
                cpu: "100m"
            volumeMounts:
            - name: script-volume
              mountPath: /scripts
              readOnly: true
          volumes:
          - name: script-volume
            secret:
              secretName: memory-test-script
              defaultMode: 0755
EOF

    print_success "CronJob created successfully"
    print_info "CronJob will trigger every minute..."
    
    echo ""
    print_info "Waiting a few seconds for the first Job to be created..."
    sleep 5
    
    # Show the current status
    kubectl get cronjobs -n "${NAMESPACE}" -l scenario=memory-intensive
    echo ""
    kubectl get jobs -n "${NAMESPACE}" -l app=memory-intensive 2>/dev/null || echo "No jobs created yet (will start within 3 minutes)"
    echo ""
    kubectl get pods -n "${NAMESPACE}" -l app=memory-intensive 2>/dev/null || echo "No pods created yet"
}

# ==============================================================================
# REVERT FAILURE (CLEANUP RESOURCES)
# ==============================================================================

revert_failure() {
    print_info "Cleaning up memory test resources from namespace: ${NAMESPACE}..."

    # Delete the CronJob (will stop creating new jobs)
    if kubectl get cronjob memory-intensive-cronjob -n "${NAMESPACE}" >/dev/null 2>&1; then
        print_info "Deleting CronJob: memory-intensive-cronjob"
        kubectl delete cronjob memory-intensive-cronjob -n "${NAMESPACE}"
        print_success "CronJob deleted"
    else
        print_info "CronJob not found, skipping"
    fi

    # Delete all Jobs created by the CronJob
    print_info "Deleting Jobs created by CronJob..."
    kubectl delete jobs -n "${NAMESPACE}" -l app=memory-intensive 2>/dev/null || true
    print_success "Jobs deleted"

    # Delete the Secret
    if kubectl get secret memory-test-script -n "${NAMESPACE}" >/dev/null 2>&1; then
        print_info "Deleting Secret: memory-test-script"
        kubectl delete secret memory-test-script -n "${NAMESPACE}"
        print_success "Secret deleted"
    else
        print_info "Secret not found, skipping"
    fi

    print_success "All resources cleaned up"
}

# ==============================================================================
# MAIN ACTIONS
# ==============================================================================

# Action: inject
action_inject() {
    # Print scenario description
    print_scenario_description

    # Note: This scenario does NOT require Bank of Anthos deployment
    # It's a standalone test

    # Check if manifests directory exists (for backup compatibility)
    # but don't require Bank of Anthos deployment
    if [ -d "${MANIFESTS_DIR}" ]; then
        create_backup
    fi

    # Deploy the failure scenario
    echo ""
    inject_failure

    echo ""
    print_success "${SCENARIO_NAME} scenario deployed successfully!"
    echo ""
    print_info "To monitor the memory limit failures:"
    echo "  • kubectl get cronjobs -n ${NAMESPACE} -l scenario=memory-intensive"
    echo "  • kubectl get jobs -n ${NAMESPACE} -l app=memory-intensive"
    echo "  • kubectl get pods -n ${NAMESPACE} -l app=memory-intensive -w"
    echo "  • kubectl describe pod -n ${NAMESPACE} -l app=memory-intensive"
    echo "  • kubectl logs -n ${NAMESPACE} -l app=memory-intensive"
    echo ""
    print_warning "CronJob will create a new pod every 3 minutes, each will be terminated within ~10 seconds due to memory limit"
    echo ""
    print_info "To clean up this scenario, run: $0 revert"
    echo ""
}

# Action: revert
action_revert() {
    echo ""
    echo "=========================================="
    echo "  Reverting ${SCENARIO_NAME} Scenario"
    echo "=========================================="
    echo ""

    # Clean up resources
    revert_failure

    echo ""
    print_success "${SCENARIO_NAME} scenario reverted successfully!"
    echo ""
    print_info "Verification:"
    echo "  • kubectl get cronjobs -n ${NAMESPACE}"
    echo "    (should show: No resources found)"
    echo ""
    echo "  • kubectl get jobs -n ${NAMESPACE}"
    echo "    (should show: No resources found)"
    echo ""
    echo "  • kubectl get pods -n ${NAMESPACE}"
    echo "    (should show: No resources found or pods terminating)"
    echo ""
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

# Handle command line arguments using common handler
handle_scenario_command "$@"


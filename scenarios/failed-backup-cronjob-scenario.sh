#!/bin/bash

# Failed Backup CronJob Scenario
# This script applies a CronJob that fails when executed at the top of the hour
#
# Usage:
#   ./failed-backup-cronjob-scenario.sh          # Inject failure (default)
#   ./failed-backup-cronjob-scenario.sh inject   # Inject failure
#   ./failed-backup-cronjob-scenario.sh revert   # Revert failure

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="FailedBackupCronJob"
SCENARIO_DESCRIPTION="Applies a CronJob that fails when the backup script detects high database load at the top of the hour"

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
    echo "  This scenario creates a CronJob that runs a ledger database backup every hour"
    echo "  at the top of the hour (minute 0). The backup script intentionally fails when"
    echo "  it detects that it's running at minute 00, simulating a database that's under"
    echo "  heavy load. This creates recurring failed jobs that need investigation."
    echo ""
    echo "Affected Services:"
    echo "  • ledger-db-backup: CronJob that fails at the top of each hour"
    echo "  • Jobs fail with exit code 1 due to database load check"
    echo ""
    echo "Expected Behavior:"
    echo "  • CronJob 'ledger-db-backup' is created with schedule '0 * * * *'"
    echo "  • Secret 'ledger-db-backup-script' contains the backup script"
    echo "  • Jobs created at minute 00 fail immediately with exit code 1"
    echo "  • Job logs show: 'ERROR: Database is under heavy load'"
    echo "  • Failed jobs are retained (failedJobsHistoryLimit: 3)"
    echo "  • Manual job triggers at other minutes succeed"
    echo ""
    echo "Observable Symptoms:"
    echo "  • kubectl get cronjobs shows 'ledger-db-backup' scheduled at '0 * * * *'"
    echo "  • kubectl get jobs shows failed jobs with 0/1 completions"
    echo "  • kubectl get pods shows completed pods with Error status"
    echo "  • kubectl logs shows database load error message"
    echo "  • kubectl describe cronjob shows last schedule time and failed status"
    echo "  • Jobs fail only at minute 00, succeed at other times"
    echo ""
    echo "Real-World Scenarios This Represents:"
    echo "  • Backup jobs that fail during peak load times"
    echo "  • Resource contention during scheduled maintenance windows"
    echo "  • Time-based failures due to external dependencies"
    echo "  • Jobs that need rescheduling to avoid conflicts"
    echo "  • Monitoring alerts for recurring job failures"
    echo "  • Database maintenance windows causing backup failures"
    echo ""
    echo "Testing the Scenario:"
    echo "  1. Wait for the top of the hour (minute 00) to see automatic failure"
    echo "  2. Or manually trigger: kubectl create job --from=cronjob/ledger-db-backup test-backup -n ${NAMESPACE}"
    echo "  3. Check job status and logs to observe the failure"
    echo ""
    echo "=========================================="
    echo ""
}

# ==============================================================================
# INJECT FAILURE
# ==============================================================================

inject_failure() {
    local yaml_file="${SCRIPT_DIR}/failed-backup-cronjob-scenario.yaml"

    if [ ! -f "$yaml_file" ]; then
        print_error "YAML file not found: ${yaml_file}"
        exit 1
    fi

    print_info "Applying CronJob with failing backup script..."

    # Replace namespace in YAML and apply
    sed "s/namespace: anthos-bank/namespace: ${NAMESPACE}/g" "$yaml_file" | \
        kubectl apply -f -

    print_success "CronJob configuration applied"
    sleep 2

    print_info "Checking CronJob status..."
    kubectl get cronjob ledger-db-backup -n "${NAMESPACE}" -o wide 2>/dev/null || true

    echo ""
    print_info "Checking existing jobs (if any)..."
    kubectl get jobs -n "${NAMESPACE}" -l app=ledger-db-backup 2>/dev/null || true

    echo ""
    print_info "Next scheduled run will be at the top of the hour (minute 00)"
    echo ""
    print_warning "The backup job will fail when executed at minute 00 due to database load check"
}

# ==============================================================================
# REVERT FAILURE
# ==============================================================================

revert_failure() {
    print_info "Removing CronJob and related resources..."

    local yaml_file="${SCRIPT_DIR}/failed-backup-cronjob-scenario.yaml"

    if [ ! -f "$yaml_file" ]; then
        print_warning "YAML file not found: ${yaml_file}"
        print_info "Attempting to delete resources manually..."

        kubectl delete cronjob ledger-db-backup -n "${NAMESPACE}" 2>/dev/null || true
        kubectl delete secret ledger-db-backup-script -n "${NAMESPACE}" 2>/dev/null || true

        # Delete any jobs created by the CronJob
        kubectl delete jobs -n "${NAMESPACE}" -l app=ledger-db-backup 2>/dev/null || true

        print_success "Resources removed"
        return
    fi

    # Replace namespace in YAML and delete
    sed "s/namespace: anthos-bank/namespace: ${NAMESPACE}/g" "$yaml_file" | \
        kubectl delete -f - 2>/dev/null || true

    # Delete any jobs created by the CronJob (they are not deleted automatically)
    kubectl delete jobs -n "${NAMESPACE}" -l app=ledger-db-backup 2>/dev/null || true

    print_success "CronJob configuration removed"
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
    echo "  • kubectl get cronjobs -n ${NAMESPACE}"
    echo "  • kubectl get jobs -n ${NAMESPACE} -l app=ledger-db-backup"
    echo "  • kubectl get pods -n ${NAMESPACE} -l app=ledger-db-backup"
    echo "  • kubectl describe cronjob ledger-db-backup -n ${NAMESPACE}"
    echo "  • kubectl logs -n ${NAMESPACE} -l app=ledger-db-backup"
    echo ""
    print_info "To manually trigger a test job:"
    echo "  • kubectl create job --from=cronjob/ledger-db-backup manual-test-\$(date +%s) -n ${NAMESPACE}"
    echo ""
    print_info "To see the failure pattern:"
    echo "  • Wait for the top of the hour (minute 00) for automatic failure"
    echo "  • Or trigger manually and check logs for database load error"
    echo ""
    print_warning "Jobs will fail at minute 00 but succeed at other times"
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
    echo "  • kubectl get cronjob ledger-db-backup -n ${NAMESPACE}"
    echo "    (Should NOT exist)"
    echo ""
    echo "  • kubectl get jobs -n ${NAMESPACE} -l app=ledger-db-backup"
    echo "    (Should NOT exist)"
    echo ""
    echo "  • kubectl get secret ledger-db-backup-script -n ${NAMESPACE}"
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

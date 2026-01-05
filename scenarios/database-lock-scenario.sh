#!/bin/bash

# Database Lock Scenario - Cascading Failure
# This script creates a database table lock causing cascading failures
#
# Usage:
#   ./database-lock-scenario.sh          # Inject failure (default)
#   ./database-lock-scenario.sh inject   # Inject failure
#   ./database-lock-scenario.sh revert   # Revert failure

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="Database Lock"
SCENARIO_DESCRIPTION="Creates an exclusive lock on the TRANSACTIONS table causing cascading failures"

# ==============================================================================
# SHARED FUNCTIONS
# ==============================================================================

# Function to print scenario description
print_scenario_description() {
    echo ""
    echo "=========================================="
    echo "  ${SCENARIO_NAME} Scenario (Cascading)"
    echo "=========================================="
    echo ""
    echo "Description:"
    echo "  This scenario creates an exclusive lock on the TRANSACTIONS table in the"
    echo "  PostgreSQL database. This simulates a scenario where a long-running query,"
    echo "  stuck transaction, or database migration locks a critical table, causing"
    echo "  cascading failures across multiple services that depend on it."
    echo ""
    echo "Affected Services:"
    echo "  • ledger-db: TRANSACTIONS table locked with ACCESS EXCLUSIVE MODE"
    echo "  • ledgerwriter: Cannot write new transactions (blocked)"
    echo "  • balancereader: Cannot read account balances (blocked)"
    echo "  • transactionhistory: Cannot query transaction history (blocked)"
    echo "  • frontend: Banking operations timeout waiting for backend"
    echo "  • contacts: May be indirectly affected"
    echo ""
    echo "Expected Behavior:"
    echo "  • SQL lock acquired on TRANSACTIONS table"
    echo "  • Lock persists for 1 hour (or until manually released)"
    echo "  • Any service attempting to query/write to TRANSACTIONS will block"
    echo "  • Database connections will queue up waiting for the lock"
    echo "  • Connection pool exhaustion in backend services"
    echo "  • Timeout errors cascade up to frontend"
    echo "  • User operations fail with timeout/error messages"
    echo ""
    echo "Observable Symptoms:"
    echo "  • ledgerwriter pods show timeout errors in logs"
    echo "  • balancereader queries hang indefinitely"
    echo "  • Frontend shows 'Service Unavailable' or timeout errors"
    echo "  • Database connection count increases"
    echo "  • pg_locks table shows exclusive lock on TRANSACTIONS"
    echo "  • Application latency metrics spike dramatically"
    echo "  • Multiple services show degraded health checks"
    echo ""
    echo "Real-World Scenarios This Represents:"
    echo "  • Long-running database migration without proper locking strategy"
    echo "  • Stuck transaction holding locks"
    echo "  • Administrative VACUUM FULL operation"
    echo "  • Application bug causing transaction to never commit/rollback"
    echo "  • Schema change (ALTER TABLE) during business hours"
    echo ""
    echo "=========================================="
    echo ""
}

# ==============================================================================
# INJECT FAILURE
# ==============================================================================

inject_failure() {
    print_info "Finding ledger-db pod..."

    local DB_POD
    DB_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=ledger-db -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$DB_POD" ]; then
        print_error "ledger-db pod not found"
        return 1
    fi

    print_success "Found pod: ${DB_POD}"
    print_info "Locking TRANSACTIONS table..."

    # Create SQL lock script that runs in the background on the pod itself
    # Use nohup to persist even after script exits
    kubectl exec -n "${NAMESPACE}" "${DB_POD}" -- bash -c \
        "nohup bash -c 'PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d postgresdb -c \"BEGIN; LOCK TABLE TRANSACTIONS IN ACCESS EXCLUSIVE MODE; SELECT pg_sleep(3600); COMMIT;\"' > /tmp/lock.log 2>&1 &" 2>/dev/null

    sleep 3

    print_success "Database table lock acquired (persistent)"
    print_info "TRANSACTIONS table is now locked - cascading failures expected"
    print_info "Lock will persist until you run './scenarios/restore.sh' or '$0 revert'"

    echo ""
    print_warning "Cascading effects:"
    echo "  • ledgerwriter: Cannot write transactions"
    echo "  • balancereader: Cannot read balances"
    echo "  • transactionhistory: Cannot query history"
    echo "  • frontend: Banking operations will timeout"
}

# ==============================================================================
# REVERT FAILURE
# ==============================================================================

revert_failure() {
    print_info "Releasing database table lock..."

    local DB_POD
    DB_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=ledger-db -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$DB_POD" ]; then
        print_warning "ledger-db pod not found, lock may have been cleared"
        return 0
    fi

    # Terminate all lock sessions on the TRANSACTIONS table
    kubectl exec -n "${NAMESPACE}" "${DB_POD}" -- bash -c \
        "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d postgresdb -c \"SELECT pg_terminate_backend(pid) FROM pg_locks WHERE relation = 'transactions'::regclass AND pid != pg_backend_pid();\"" 2>/dev/null || true

    print_success "Database lock released"
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
    echo "  • kubectl logs -f deployment/ledgerwriter -n ${NAMESPACE}"
    echo "  • kubectl logs -f deployment/balancereader -n ${NAMESPACE}"
    echo "  • kubectl get pods -n ${NAMESPACE} -w"
    echo ""
    print_info "To check database locks:"
    echo "  DB_POD=\$(kubectl get pods -n ${NAMESPACE} -l app=ledger-db -o jsonpath='{.items[0].metadata.name}')"
    echo "  kubectl exec -n ${NAMESPACE} \${DB_POD} -- psql -U \$POSTGRES_USER -d postgresdb -c \"SELECT * FROM pg_locks WHERE relation='transactions'::regclass;\""
    echo ""
    print_info "To revert this scenario and release lock, run: $0 revert"
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
    echo "  • Services should be able to write/read from TRANSACTIONS table again"
    echo "  • Check that lock is gone:"
    echo "    DB_POD=\$(kubectl get pods -n ${NAMESPACE} -l app=ledger-db -o jsonpath='{.items[0].metadata.name}')"
    echo "    kubectl exec -n ${NAMESPACE} \${DB_POD} -- psql -U \$POSTGRES_USER -d postgresdb -c \"SELECT * FROM pg_locks WHERE relation='transactions'::regclass;\""
    echo ""
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

# Handle command line arguments using common handler
handle_scenario_command "$@"

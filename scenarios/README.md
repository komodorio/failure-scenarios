# Bank of Anthos - Failure Injection Scenarios

This directory contains individual failure scenario scripts for testing monitoring and observability tools with Bank of Anthos. Each scenario is a self-contained unit that can inject a failure and revert it independently.

## Structure

```
scenarios/
├── common.sh                         # Shared functions and variables
├── bad-deployment-scenario.sh        # Failed deployment scenario
├── config-misconfigured-scenario.sh  # Configuration error scenario
├── database-lock-scenario.sh         # Database lock cascading failure
├── helm-bad-upgrade-scenario.sh      # Failed Helm upgrade scenario
├── high-load-scenario.sh             # High CPU load scenario
├── limit-range-contacts-scenario.sh  # Resource limit violation scenario
├── network-policy-scenario.sh        # Network connectivity failure scenario
├── node-selector-scenario.sh         # Pod scheduling failure scenario
├── oom-killed-scenario.sh            # Out-of-Memory scenario
├── resource-quota-scenario.sh        # Namespace quota violation scenario
├── restore.sh                        # Restore all scenarios to normal state
└── README.md                         # This file
```

## New Self-Contained Architecture

Each scenario now supports both **inject** and **revert** actions:

```bash
# Inject a failure (default action)
./scenarios/bad-deployment-scenario.sh
./scenarios/bad-deployment-scenario.sh inject

# Revert the failure
./scenarios/bad-deployment-scenario.sh revert
```

This architecture provides:
- **Isolated Units**: Each scenario knows how to clean up its own failures
- **No Duplication**: Revert logic lives in one place per scenario
- **Easy Maintenance**: Changes to a scenario only need to be made in one file
- **Flexible Usage**: Run individual scenarios or use `restore.sh` to revert all

## Benefits of Separated Scenarios

- **No Git Conflicts**: Multiple team members can work on different scenarios simultaneously
- **Clear Ownership**: Each scenario is independently managed
- **Better Documentation**: Each script includes detailed descriptions of the failure and expected behavior
- **Easier Testing**: Test individual scenarios without affecting others
- **Modular Design**: Easy to add new scenarios without modifying existing ones
- **Self-Contained**: Each scenario can inject and revert its own failures

## Usage

### Individual Scenario Testing

Each scenario script supports two actions: `inject` (default) and `revert`.

```bash
# Inject a failure (from project root)
./scenarios/network-policy-scenario.sh          # Default: inject
./scenarios/network-policy-scenario.sh inject   # Explicit inject

# Revert the failure
./scenarios/network-policy-scenario.sh revert

# Works from scenarios directory too
cd scenarios
./network-policy-scenario.sh          # Inject
./network-policy-scenario.sh revert   # Revert
```

### Multi-Namespace Testing

Use the `NAMESPACE` environment variable to target specific namespaces:

```bash
# Inject failure to specific namespace
NAMESPACE="bad-deployment-scenario" ./scenarios/bad-deployment-scenario.sh inject

# Revert failure in specific namespace
NAMESPACE="bad-deployment-scenario" ./scenarios/bad-deployment-scenario.sh revert
```

### Interactive Menu (from project root)

```bash
./inject-failure.sh  # Original interactive menu for user namespace
./start.sh          # Master menu for multi-namespace operations
```

### Restore All Scenarios

The `restore.sh` script now delegates to each scenario's revert action:

```bash
# Restore all scenarios in current namespace
./scenarios/restore.sh

# Restore all scenarios in specific namespace
NAMESPACE="bad-deployment-scenario" ./scenarios/restore.sh
```

## Scenario Details

### 1. Bad Deployment (`bad-deployment-scenario.sh`)
**Description**: Updates ledgerwriter to use a non-existent image tag (v999.99.99)

**Affected Services**:
- ledgerwriter (invalid image)

**Expected Behavior**:
- ImagePullBackOff status
- Rollout stalled
- Old pods continue running
- Deployment marked as Progressing

**Revert**: Restores correct image version and replica count

---

### 2. Config Misconfigured (`config-misconfigured-scenario.sh`)
**Description**: Renames SPRING_DATASOURCE_URL to SPRING_DATASOURCE_URL_oops in ConfigMap

**Affected Services**:
- ledgerwriter (cannot connect to database)

**Expected Behavior**:
- Database connection errors
- CrashLoopBackOff or Error status
- Service unavailability

**Revert**: Restores correct ConfigMap key name and restarts pods

---

### 3. Database Lock (`database-lock-scenario.sh`)
**Description**: Creates exclusive lock on TRANSACTIONS table causing cascading failures

**Affected Services**:
- ledger-db (TRANSACTIONS table locked)
- ledgerwriter (blocked)
- balancereader (blocked)
- transactionhistory (blocked)
- frontend (timeouts)

**Expected Behavior**:
- Database queries hang
- Connection pool exhaustion
- Cascading timeout errors
- Multiple service degradation

**Revert**: Releases database table locks

---

### 4. Helm Bad Upgrade (`helm-bad-upgrade-scenario.sh`)
**Description**: Deploys cash-cache (Redis) with invalid configuration flag

**Affected Services**:
- cash-cache (invalid Redis configuration)

**Expected Behavior**:
- CrashLoopBackOff status
- Redis fails to start
- Container restart count increases

**Revert**: Restores Helm release with default values

---

### 5. High Load (`high-load-scenario.sh`)
**Description**: Increases load generator from 5 to 200 concurrent users

**Affected Services**:
- loadgenerator (200 concurrent users)
- users service (high CPU)
- frontend (crashes)

**Expected Behavior**:
- High CPU usage
- CPU throttling
- Service instability
- Possible pod restarts

**Revert**: Resets load generator to 5 users

---

### 6. LimitRange (`limit-range-contacts-scenario.sh`)
**Description**: Creates restrictive LimitRange preventing contacts deployment from restarting

**Affected Services**:
- contacts (cannot restart due to LimitRange)

**Expected Behavior**:
- Pod creation fails
- FailedCreate events
- Deployment shows 0/1 ready

**Revert**: Removes restrictive LimitRange

---

### 7. Network Policy (`network-policy-scenario.sh`)
**Description**: Creates NetworkPolicy blocking userservice from accessing accounts-db

**Affected Services**:
- accounts-db (NetworkPolicy blocks ingress)
- userservice (cannot connect to database)
- frontend (user operations fail)

**Expected Behavior**:
- userservice shows NotReady (0/1)
- Readiness probe fails
- Connection timeouts
- Service unavailable

**Revert**: Removes blocking NetworkPolicy

---

### 8. Node Selector (`node-selector-scenario.sh`)
**Description**: Adds nodeSelector with non-existent labels causing pods to be unschedulable

**Affected Services**:
- balancereader (unschedulable)

**Expected Behavior**:
- Pod stuck in Pending state
- FailedScheduling events
- Deployment shows 0/1 ready

**Revert**: Removes nodeSelector from deployment

---

### 9. OOM Killed (`oom-killed-scenario.sh`)
**Description**: Reduces transactionhistory memory limits to cause OOMKilled events

**Affected Services**:
- transactionhistory (unreasonably low memory limits)

**Expected Behavior**:
- OOMKilled pod status
- CrashLoopBackOff
- High restart count
- Service unavailability

**Revert**: Restores memory limits and JVM settings

---

### 10. Resource Quota (`resource-quota-scenario.sh`)
**Description**: Creates restrictive ResourceQuota causing pod creation failures

**Affected Services**:
- userservice (scaled to 5 replicas, fails to create new pods)
- All deployments in namespace

**Expected Behavior**:
- Pod creation fails
- Quota exceeded errors
- Deployment shows unhealthy state (e.g., 1/5 ready)

**Revert**: Removes ResourceQuota and scales userservice back to 1

## Adding New Scenarios

To add a new failure scenario:

1. Create a new script following the naming convention: `scenarios/your-scenario-name-scenario.sh`

2. Follow this template structure:

```bash
#!/bin/bash

# Your Scenario Name
# Description of what this scenario does
#
# Usage:
#   ./your-scenario-name-scenario.sh          # Inject failure (default)
#   ./your-scenario-name-scenario.sh inject   # Inject failure
#   ./your-scenario-name-scenario.sh revert   # Revert failure

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ==============================================================================
# SCENARIO METADATA
# ==============================================================================

SCENARIO_NAME="YourScenarioName"
SCENARIO_DESCRIPTION="Brief description of what the scenario does"

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
    echo "  Detailed description..."
    echo ""
    echo "Affected Services:"
    echo "  • service1: description"
    echo ""
    echo "Expected Behavior:"
    echo "  • behavior 1"
    echo ""
    echo "Observable Symptoms:"
    echo "  • symptom 1"
    echo ""
    echo "Real-World Scenarios This Represents:"
    echo "  • scenario 1"
    echo ""
    echo "=========================================="
    echo ""
}

# ==============================================================================
# INJECT FAILURE
# ==============================================================================

inject_failure() {
    print_info "Injecting failure..."

    # Your failure injection code here

    print_success "Failure injected successfully"
}

# ==============================================================================
# REVERT FAILURE
# ==============================================================================

revert_failure() {
    print_info "Reverting failure..."

    # Your revert code here
    # This should undo everything that inject_failure() did

    print_success "Failure reverted successfully"
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
    echo "  • kubectl get pods -n ${NAMESPACE}"
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
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

# Handle command line arguments using common handler
handle_scenario_command "$@"
```

3. Make it executable:
```bash
chmod +x scenarios/your-scenario-name-scenario.sh
```

4. Test it:
```bash
# Test inject
./scenarios/your-scenario-name-scenario.sh inject

# Test revert
./scenarios/your-scenario-name-scenario.sh revert
```

5. Submit a pull request

**No other code changes needed!**
- Scenarios are auto-discovered by batch scripts
- `restore.sh` automatically calls your scenario's revert action
- Follows consistent pattern with all other scenarios

## Prerequisites

- Bank of Anthos must be deployed
- kubectl configured to access the cluster
- jq installed (for JSON processing)
- Proper permissions to modify deployments
- helm installed (for Helm scenarios)

## Monitoring Commands

After injecting a scenario, monitor with:

```bash
# Watch pods
kubectl get pods -n ${NAMESPACE} -w

# Check resource usage
kubectl top pods -n ${NAMESPACE}

# View events
kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp'

# Check deployment status
kubectl get deployments -n ${NAMESPACE}

# View logs
kubectl logs -f deployment/<service-name> -n ${NAMESPACE}
```

## Troubleshooting

If a scenario script fails:

1. Check that Bank of Anthos is deployed: `kubectl get pods -n ${NAMESPACE}`
2. Verify you're in the correct directory
3. Ensure backup directory exists
4. Run the scenario's revert action: `./scenarios/<scenario>.sh revert`
5. Or restore all: `./scenarios/restore.sh`
6. Check kubectl access to cluster: `kubectl get ns`

## Best Practices

- Each scenario can inject and revert its own failures independently
- Test inject and revert actions when creating new scenarios
- Document expected behavior and revert actions clearly
- Monitor the effects before considering a scenario successful
- Use `$0 revert` instead of hardcoding `./scenarios/restore.sh`
- Keep backup directory intact for rollback capability
- Follow the naming convention: `*-scenario.sh`

## Common Functions (from common.sh)

All scenarios have access to these shared functions:

- `print_info "message"` - Blue informational message
- `print_success "message"` - Green success message
- `print_warning "message"` - Yellow warning message
- `print_error "message"` - Red error message
- `check_deployment()` - Verify Bank of Anthos is deployed
- `check_manifests()` - Verify manifests directory exists
- `create_backup()` - Create backup of original manifests
- `handle_scenario_command "$@"` - Handle inject/revert command-line arguments

## Architecture

The scenarios follow a consistent pattern:

1. **SCENARIO METADATA** - Define scenario name and description
2. **SHARED FUNCTIONS** - Helper functions including scenario description
3. **INJECT FAILURE** - Function to inject the failure
4. **REVERT FAILURE** - Function to revert the failure
5. **MAIN ACTIONS** - `action_inject()` and `action_revert()` orchestration
6. **ENTRY POINT** - Single line calling `handle_scenario_command "$@"`

This architecture ensures:
- Consistency across all scenarios
- Easy maintenance and updates
- Self-contained inject/revert capabilities
- Minimal code duplication
- Automatic integration with batch scripts

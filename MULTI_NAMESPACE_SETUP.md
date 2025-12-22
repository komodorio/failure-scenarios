# Multi-Namespace Scenario Setup

This document describes how to deploy Bank of Anthos to multiple namespaces, one for each failure scenario.

## Overview

The multi-namespace setup allows you to:
- Deploy Bank of Anthos to separate namespaces for each scenario
- Run multiple scenarios in parallel without interference
- Test scenarios in isolation

All scripts automatically discover available scenarios from the `scenarios/` directory, so adding new scenarios requires no code changes.

## Quick Start - Master Menu

The easiest way to manage multi-namespace scenarios is through the master menu:

```bash
./start.sh
```

This provides an interactive menu with all operations:
1. **Setup All Scenarios** - Deploy Bank of Anthos to all scenario namespaces
2. **Check All Scenarios** - Check status of all scenario namespaces
3. **Inject All Scenarios** - Inject failures in all namespaces (parallel)
4. **Inject by Namespace** - Inject failure in specific namespace (interactive)
5. **Restore All Scenarios** - Restore all namespaces to normal state (parallel)
6. **Restore by Namespace** - Restore specific namespace (interactive)
7. **Cleanup All Scenarios** - Delete all scenario namespaces (parallel)

All individual scripts are located in the `batch/` directory and can also be run directly.

## Scripts

### 1. `batch/setup-all-scenarios.sh`

Deploys Bank of Anthos to separate namespaces for each scenario.

**Usage:**
```bash
./batch/setup-all-scenarios.sh
```

**What it does:**
- Creates a namespace for each scenario (e.g., `bad-deployment-scenario`, `database-lock-scenario`, etc.)
- Deploys Bank of Anthos to each namespace in parallel
- Does NOT wait for pods to be ready (for maximum speed)
- Pods start in the background while continuing with next namespace
- Completes in ~30-45 seconds for 10 namespaces

**Namespaces created:**
- `high-load-scenario`
- `oom-killed-scenario`
- `bad-deployment-scenario`
- `database-lock-scenario`
- `resource-quota-scenario`
- `helm-bad-upgrade-scenario`
- `limit-range-contacts-scenario`
- `network-policy-scenario`
- `node-selector-scenario`
- `config-misconfigured-scenario`

### 2. `batch/check-all-scenarios.sh`

Checks the status of all scenario namespaces.

**Usage:**
```bash
./batch/check-all-scenarios.sh
```

**What it does:**
- Checks if each scenario namespace exists
- Reports deployment readiness status
- Shows summary of ready/not ready/missing namespaces
- Displays pods that are not ready

**Example output:**
```
✓ bad-deployment-scenario - All pods ready
⚠ database-lock-scenario - 2 deployment(s) not ready
✓ helm-bad-upgrade-scenario - All pods ready

Summary:
Total scenario namespaces: 10
Ready: 8
Not ready: 2
```

### 3. `batch/inject-all-scenarios.sh`

Injects all failure scenarios to their respective namespaces in parallel.

**Usage:**
```bash
./batch/inject-all-scenarios.sh
```

**What it does:**
- Checks which scenario namespaces exist
- Injects each scenario into its corresponding namespace in parallel
- Runs all injections concurrently for maximum speed
- Reports success/failure for each scenario
- Saves logs to `/tmp/<scenario-name>-injection.log`

**Example:**
```bash
$ ./batch/inject-all-scenarios.sh

This script will inject failures in 10 namespaces:
  ✓ bad-deployment-scenario
  ✓ database-lock-scenario
  ✓ helm-bad-upgrade-scenario
  ...

Will inject failures in 10 namespace(s)
Do you want to proceed? (y/n): y

Injecting failures in parallel...
Starting: bad-deployment → bad-deployment-scenario
Starting: database-lock → database-lock-scenario
...

Summary:
Successfully injected: 10
Failed: 0
```

### 4. `batch/inject-failure-by-namespace.sh`

Interactive script to inject failures into specific namespaces.

**Usage:**
```bash
./batch/inject-failure-by-namespace.sh
```

**Features:**
- Interactive menu to select scenario
- Choose target namespace:
  - Scenario-specific namespace (e.g., `bad-deployment-scenario`)
  - User namespace (e.g., `anthos-bank-${USER}`)
  - Custom namespace

**Example:**
```bash
$ ./batch/inject-failure-by-namespace.sh
# Select scenario: 3 (Bad Deployment)
# Select namespace: 1 (bad-deployment-scenario)
# Script injects failure into bad-deployment-scenario namespace
```

### 5. `batch/restore-all-scenarios.sh`

Restores all failure scenarios in their respective namespaces in parallel.

**Usage:**
```bash
./batch/restore-all-scenarios.sh
```

**What it does:**
- Checks which scenario namespaces exist
- Restores each scenario to normal state in parallel
- Runs all restores concurrently for maximum speed
- Reports success/failure for each scenario
- Saves logs to `/tmp/<scenario-name>-restore.log`

### 6. `batch/restore-by-namespace.sh`

Interactive script to restore specific namespaces to normal state.

**Usage:**
```bash
./batch/restore-by-namespace.sh
```

**Features:**
- Interactive menu to select scenario
- Choose target namespace
- Confirmation before restoration
- Restores all services to normal state

### 7. `batch/cleanup-all-scenarios.sh`

Removes all scenario-specific namespaces.

**Usage:**
```bash
./batch/cleanup-all-scenarios.sh
```

**What it does:**
- Lists all existing scenario namespaces
- Prompts for confirmation
- Deletes all namespaces in parallel with force deletion
- Completes in ~30-60 seconds for 10 namespaces

## Namespace Override

All scenario scripts support namespace override via environment variable:

```bash
# Run scenario in specific namespace
NAMESPACE="bad-deployment-scenario" ./scenarios/bad-deployment-scenario.sh

# Restore specific namespace
NAMESPACE="bad-deployment-scenario" ./scenarios/restore.sh
```

## Original Behavior

The original `setup-bank-of-anthos.sh` script still works as before:
- Deploys to user-specific namespace (`anthos-bank-${USER}`)
- Can be run independently of multi-namespace setup

The original `inject-failure.sh` script still works as before:
- Targets user-specific namespace by default
- No changes to existing workflow

## Workflow Examples

### Using the Master Menu (Recommended)
```bash
# Launch the interactive menu
./start.sh

# Then select from menu:
# 1 - Setup all scenarios
# 2 - Check status
# 3 - Inject all failures
# 4 - Inject specific failure
# 5 - Restore all scenarios
# 6 - Restore specific scenario
# 7 - Cleanup all scenarios
```

### Complete End-to-End Workflow (Direct Scripts)
```bash
# 1. Deploy all scenarios to separate namespaces
./batch/setup-all-scenarios.sh
# Completes in ~30-45 seconds

# 2. Wait a bit for pods to start, then check status
./batch/check-all-scenarios.sh

# 3. Inject all failures in parallel
./batch/inject-all-scenarios.sh
# Completes in ~1-2 minutes

# 4. Monitor the failures
./batch/check-all-scenarios.sh
kubectl get pods -n bad-deployment-scenario
kubectl get pods -n database-lock-scenario

# 5. Restore all scenarios
./batch/restore-all-scenarios.sh
# Completes in ~1-2 minutes

# 6. Cleanup when done
./batch/cleanup-all-scenarios.sh
# Completes in ~30-60 seconds
```

### Deploy to all scenario namespaces
```bash
./batch/setup-all-scenarios.sh
```

### Inject all scenarios in parallel
```bash
./batch/inject-all-scenarios.sh
```

### Inject failure to specific scenario namespace
```bash
./batch/inject-failure-by-namespace.sh
# Choose scenario and namespace from menu
```

### Or use environment variable
```bash
NAMESPACE="bad-deployment-scenario" ./scenarios/bad-deployment-scenario.sh
```

### Check status of all namespaces
```bash
./batch/check-all-scenarios.sh
```

### Restore all scenarios
```bash
./batch/restore-all-scenarios.sh
```

### Restore specific scenario namespace
```bash
./batch/restore-by-namespace.sh
# Choose scenario and namespace from menu
```

### Or use environment variable for restore
```bash
NAMESPACE="bad-deployment-scenario" ./scenarios/restore.sh
```

### View pods in specific namespace
```bash
kubectl get pods -n bad-deployment-scenario
kubectl get pods -n database-lock-scenario
```

### Cleanup all scenario namespaces
```bash
./batch/cleanup-all-scenarios.sh
```

## Use Cases

### Parallel Testing
Run different scenarios in parallel without interference:
```bash
# Terminal 1
NAMESPACE="bad-deployment-scenario" ./scenarios/bad-deployment-scenario.sh

# Terminal 2
NAMESPACE="database-lock-scenario" ./scenarios/database-lock-scenario.sh

# Terminal 3
NAMESPACE="oom-killed-scenario" ./scenarios/oom-killed-scenario.sh
```

### Persistent Test Environments
Keep scenarios deployed for extended testing:
```bash
# Deploy all scenarios
./setup-all-scenarios.sh

# Inject failures as needed
NAMESPACE="bad-deployment-scenario" ./scenarios/bad-deployment-scenario.sh
NAMESPACE="helm-bad-upgrade-scenario" ./scenarios/helm-bad-upgrade-scenario.sh

# Scenarios remain isolated in their namespaces
# No need to restore between tests
```

### Scenario Comparison
Compare behavior across different scenarios:
```bash
# Watch pods in different namespaces
kubectl get pods -n bad-deployment-scenario -w
kubectl get pods -n oom-killed-scenario -w
```

## Shared Library

All multi-namespace scripts use a shared library for common functionality:

**`lib/common-helpers.sh`** - Contains:
- Color-coded output functions (`print_info`, `print_success`, `print_warning`, `print_error`)
- `discover_scenarios()` - Dynamically finds all `*-scenario.sh` files
- `scenario_to_title_case()` - Converts scenario names to display format

This ensures consistency across scripts and eliminates code duplication.

## Notes

- Each namespace deployment is independent
- Namespaces can be managed individually
- Original user-namespace workflow unchanged
- All scenario scripts support namespace override
- Helm releases are namespace-scoped
- Scripts automatically discover scenarios - no hardcoded lists
- Adding new scenarios requires no code changes

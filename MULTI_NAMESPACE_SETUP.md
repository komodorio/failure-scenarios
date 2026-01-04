# Multi-Namespace Scenario Setup

This document describes how to deploy Bank of Anthos to multiple namespaces, one for each failure scenario.

## Overview

The multi-namespace setup allows you to:
- Deploy Bank of Anthos to separate namespaces for each scenario
- Run multiple scenarios in parallel without interference
- Test scenarios in isolation
- Use creative, movie-themed namespace names for easy identification

All scripts automatically discover available scenarios from the `scenarios/` directory, so adding new scenarios requires no code changes.

## Namespace Naming

Each scenario is deployed to a custom namespace inspired by fictional cities from movies. The mapping is defined in [config/namespace-mapping.conf](config/namespace-mapping.conf):

| Scenario | Namespace Base | Movie/Show | Full Namespace Example |
|----------|---------------|------------|------------------------|
| bad-deployment | bank-of-springfield | The Simpsons Movie | bank-of-springfield-{timestamp} |
| config-misconfigured | bank-of-hill-valley | Back to the Future | bank-of-hill-valley-{timestamp} |
| database-lock | bank-of-punxsutawney | Groundhog Day | bank-of-punxsutawney-{timestamp} |
| helm-bad-upgrade | bank-of-bedford-falls | It's a Wonderful Life | bank-of-bedford-falls-{timestamp} |
| high-load | bank-of-seahaven | The Truman Show | bank-of-seahaven-{timestamp} |
| limit-range-contacts | bank-of-sandford | Hot Fuzz | bank-of-sandford-{timestamp} |
| network-policy | bank-of-twin-peaks | Twin Peaks | bank-of-twin-peaks-{timestamp} |
| node-selector | bank-of-pleasantville | Pleasantville | bank-of-pleasantville-{timestamp} |
| oom-killed | bank-of-radiator-springs | Cars | bank-of-radiator-springs-{timestamp} |
| resource-quota | bank-of-whoville | The Grinch | bank-of-whoville-{timestamp} |
| failed-backup-cronjob | bank-of-arendelle | Frozen | bank-of-arendelle-{timestamp} |
| kyverno-policy | bank-of-koriko | Kiki's Delivery Service | bank-of-koriko-{timestamp} |
| missing-storage-class | bank-of-mos-eisley | Star Wars | bank-of-mos-eisley-{timestamp} |
| wrong-sa | bank-of-hogsmeade | Harry Potter | bank-of-hogsmeade-{timestamp} |

The timestamp suffix ensures isolation between different deployment batches.

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
- Creates a namespace for each scenario with creative movie-themed names (e.g., `bank-of-springfield-{timestamp}`, `bank-of-punxsutawney-{timestamp}`, etc.)
- Deploys Bank of Anthos to each namespace in parallel
- Does NOT wait for pods to be ready (for maximum speed)
- Pods start in the background while continuing with next namespace
- Completes in ~30-45 seconds for 10+ namespaces

**Example namespaces created:**
- `bank-of-springfield-{timestamp}` (bad-deployment)
- `bank-of-hill-valley-{timestamp}` (config-misconfigured)
- `bank-of-punxsutawney-{timestamp}` (database-lock)
- `bank-of-seahaven-{timestamp}` (high-load)
- `bank-of-radiator-springs-{timestamp}` (oom-killed)
- `bank-of-whoville-{timestamp}` (resource-quota)
- And more! See the [Namespace Naming](#namespace-naming) section above.

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
✓ bank-of-springfield-20260102-100000 - All pods ready
⚠ bank-of-punxsutawney-20260102-100000 - 2 deployment(s) not ready
✓ bank-of-bedford-falls-20260102-100000 - All pods ready

Summary:
Total scenario namespaces: 14
Ready: 12
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

This script will inject failures in 14 namespaces:
  ✓ bank-of-springfield-20260102-100000
  ✓ bank-of-punxsutawney-20260102-100000
  ✓ bank-of-bedford-falls-20260102-100000
  ...

Will inject failures in 14 namespace(s)
Do you want to proceed? (y/n): y

Injecting failures in parallel...
Starting: bad-deployment → bank-of-springfield-20260102-100000
Starting: database-lock → bank-of-punxsutawney-20260102-100000
...

Summary:
Successfully injected: 14
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
  - Scenario-specific namespace (e.g., `bank-of-springfield-20260102-100000`)
  - User namespace (e.g., `anthos-bank-${USER}`)
  - Custom namespace

**Example:**
```bash
$ ./batch/inject-failure-by-namespace.sh
# Select scenario: 3 (Bad Deployment)
# Select namespace: 1 (bank-of-springfield-20260102-100000)
# Script injects failure into bank-of-springfield-20260102-100000 namespace
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
# Run scenario in specific namespace (use actual namespace with timestamp)
NAMESPACE="bank-of-springfield-20260102-100000" ./scenarios/bad-deployment-scenario.sh

# Restore specific namespace
NAMESPACE="bank-of-springfield-20260102-100000" ./scenarios/restore.sh
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
kubectl get pods -n bank-of-springfield-20260102-100000
kubectl get pods -n bank-of-punxsutawney-20260102-100000

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
NAMESPACE="bank-of-springfield-20260102-100000" ./scenarios/bad-deployment-scenario.sh
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
NAMESPACE="bank-of-springfield-20260102-100000" ./scenarios/restore.sh
```

### View pods in specific namespace
```bash
kubectl get pods -n bank-of-springfield-20260102-100000
kubectl get pods -n bank-of-punxsutawney-20260102-100000
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
NAMESPACE="bank-of-springfield-20260102-100000" ./scenarios/bad-deployment-scenario.sh

# Terminal 2
NAMESPACE="bank-of-punxsutawney-20260102-100000" ./scenarios/database-lock-scenario.sh

# Terminal 3
NAMESPACE="bank-of-radiator-springs-20260102-100000" ./scenarios/oom-killed-scenario.sh
```

### Persistent Test Environments
Keep scenarios deployed for extended testing:
```bash
# Deploy all scenarios
./batch/setup-all-scenarios.sh

# Inject failures as needed
NAMESPACE="bank-of-springfield-20260102-100000" ./scenarios/bad-deployment-scenario.sh
NAMESPACE="bank-of-bedford-falls-20260102-100000" ./scenarios/helm-bad-upgrade-scenario.sh

# Scenarios remain isolated in their namespaces
# No need to restore between tests
```

### Scenario Comparison
Compare behavior across different scenarios:
```bash
# Watch pods in different namespaces
kubectl get pods -n bank-of-springfield-20260102-100000 -w
kubectl get pods -n bank-of-radiator-springs-20260102-100000 -w
```

## Customizing Namespace Names

You can customize the namespace names by editing [config/namespace-mapping.conf](config/namespace-mapping.conf):

```bash
# Format: scenario-name=namespace-base
bad-deployment=bank-of-springfield
config-misconfigured=bank-of-hill-valley
# Add your custom mappings here
```

**Adding a new mapping:**
1. Edit `config/namespace-mapping.conf`
2. Add a line: `scenario-name=custom-namespace-base`
3. The scenario will deploy to `custom-namespace-base-{timestamp}`

**Removing a mapping:**
- Delete or comment out the line
- The scenario will use the default naming: `{scenario-name}-scenario-{timestamp}`

**Requirements:**
- Namespace names must be valid Kubernetes names (lowercase, alphanumeric, hyphens)
- Maximum length: 63 characters (including the timestamp suffix)
- No duplicate mappings (each scenario should map to a unique namespace)

## Shared Library

All multi-namespace scripts use a shared library for common functionality:

**`lib/common-helpers.sh`** - Contains:
- Color-coded output functions (`print_info`, `print_success`, `print_warning`, `print_error`)
- `discover_scenarios()` - Dynamically finds all `*-scenario.sh` files
- `scenario_to_title_case()` - Converts scenario names to display format
- `get_namespace_base()` - Looks up custom namespace mappings from config

This ensures consistency across scripts and eliminates code duplication.

## Notes

- Each namespace deployment is independent
- Namespaces can be managed individually
- Original user-namespace workflow unchanged
- All scenario scripts support namespace override
- Helm releases are namespace-scoped
- Scripts automatically discover scenarios - no hardcoded lists
- Adding new scenarios requires no code changes

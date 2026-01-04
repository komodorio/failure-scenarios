# Bank of Anthos Failure Scenarios System

This repository contains a comprehensive failure injection and testing system for Bank of Anthos on Kubernetes. It enables automated testing of various failure scenarios in isolated namespaces.

## Architecture Overview

### Core Components

1. **Multi-Namespace Deployment System**
   - Deploys Bank of Anthos to separate namespaces for each failure scenario
   - Each scenario gets its own isolated namespace with creative movie-themed names (e.g., `bank-of-springfield`, `bank-of-punxsutawney`)
   - Namespaces include timestamp suffix for batch isolation (e.g., `bank-of-springfield-20260102-100000`)
   - Custom namespace mapping via [config/namespace-mapping.conf](config/namespace-mapping.conf)
   - Original user-namespace workflow remains unchanged for backward compatibility

2. **Failure Scenarios** ([scenarios/](scenarios/))
   - Self-contained scripts that inject specific failure conditions
   - All scenarios follow naming pattern: `*-scenario.sh`
   - Automatically discovered by deployment system - no hardcoded lists
   - Support namespace override via `NAMESPACE` environment variable

3. **Shared Library** ([lib/common-helpers.sh](lib/common-helpers.sh))
   - Central utilities used by all multi-namespace scripts
   - Color-coded output functions for consistent UX
   - `discover_scenarios()` - Dynamic scenario discovery from filesystem
   - `scenario_to_title_case()` - Display name conversion
   - `get_namespace_base()` - Namespace mapping lookup (bash 3.x compatible)
   - State management functions for timestamp coordination

4. **Configuration** ([config/](config/))
   - [namespace-mapping.conf](config/namespace-mapping.conf) - Maps scenarios to custom namespace names
   - Simple key=value format, bash 3.x compatible
   - Fictional movie cities theme for easy identification

5. **Management Scripts** ([batch/](batch/))
   - [setup-all-scenarios.sh](batch/setup-all-scenarios.sh) - Deploy to all scenario namespaces (~3 min)
   - [inject-all-scenarios.sh](batch/inject-all-scenarios.sh) - Inject all failures in parallel (~1-2 min)
   - [inject-failure-by-namespace.sh](batch/inject-failure-by-namespace.sh) - Interactive single injection
   - [check-all-scenarios.sh](batch/check-all-scenarios.sh) - Status checking utility
   - [cleanup-all-scenarios.sh](batch/cleanup-all-scenarios.sh) - Namespace cleanup

## Common Commands

### Quick Start - Complete Workflow
```bash
# 1. Deploy all scenarios to separate namespaces
./setup-all-scenarios.sh

# 2. Wait a bit for pods to start, then check status
./check-all-scenarios.sh

# 3. Inject all failures in parallel
./inject-all-scenarios.sh

# 4. Monitor failures
kubectl get pods -n bad-deployment-scenario
kubectl get pods -n database-lock-scenario

# 5. Cleanup when done
./cleanup-all-scenarios.sh
```

### Individual Namespace Operations
```bash
# Deploy to specific namespace
NAMESPACE="bad-deployment-scenario" ./scenarios/bad-deployment-scenario.sh

# Check specific namespace
kubectl get pods -n bad-deployment-scenario -w

# Restore specific namespace
NAMESPACE="bad-deployment-scenario" ./scenarios/restore.sh
```

### Original User Namespace Workflow
```bash
# Deploy to user namespace (anthos-bank-${USER})
./setup-bank-of-anthos.sh

# Inject failure interactively
./inject-failure.sh
```

## Available Failure Scenarios

- **bad-deployment** - Broken pod configuration causing deployment failures
- **config-misconfigured** - Invalid configuration leading to runtime errors
- **database-lock** - Database locking/deadlock conditions
- **helm-bad-upgrade** - Failed Helm upgrade scenarios
- **high-load** - CPU/memory stress testing
- **limit-range-contacts** - Resource limit violations
- **network-policy** - Network connectivity failures
- **node-selector** - Pod scheduling failures
- **oom-killed** - Out-of-memory scenarios
- **resource-quota** - Namespace quota violations

## Key Architectural Decisions

### 1. Dynamic Scenario Discovery
**Why**: Adding new scenarios should require zero code changes to deployment scripts.

**How**: The `discover_scenarios()` function scans the `scenarios/` directory for files matching `*-scenario.sh` pattern.

**Location**: [lib/common-helpers.sh:16-33](lib/common-helpers.sh#L16-L33)

```bash
discover_scenarios() {
    local project_root="${1:-.}"
    local scenarios=()
    for scenario_file in "${project_root}/scenarios"/*-scenario.sh; do
        if [ -f "$scenario_file" ]; then
            local filename=$(basename "$scenario_file")
            local scenario_name="${filename%-scenario.sh}"
            scenarios+=("$scenario_name")
        fi
    done
    # Sort scenarios alphabetically
    if [ ${#scenarios[@]} -gt 0 ]; then
        IFS=$'\n' scenarios=($(sort <<<"${scenarios[@]}"))
        unset IFS
    fi
    echo "${scenarios[@]}"
}
```

### 2. Custom Namespace Mapping (Bash 3.x Compatible)
**Why**: Creative, meaningful namespace names improve identification and user experience. However, macOS uses bash 3.2 which doesn't support associative arrays.

**How**: Simple grep-based lookup from config file instead of associative arrays.

**Location**: [lib/common-helpers.sh:65-92](lib/common-helpers.sh#L65-L92)

```bash
get_namespace_base() {
    local scenario="$1"
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_file="${script_dir}/../config/namespace-mapping.conf"

    # If config file doesn't exist, use default
    if [ ! -f "$config_file" ]; then
        echo "${scenario}-scenario"
        return
    fi

    # Look up the scenario in the config file
    local mapped_namespace
    mapped_namespace=$(grep "^${scenario}=" "$config_file" 2>/dev/null | cut -d'=' -f2 | xargs)

    # Return mapped namespace or default
    if [ -n "$mapped_namespace" ]; then
        echo "$mapped_namespace"
    else
        echo "${scenario}-scenario"
    fi
}
```

**Configuration**: [config/namespace-mapping.conf](config/namespace-mapping.conf)
```bash
bad-deployment=bank-of-springfield
database-lock=bank-of-punxsutawney
high-load=bank-of-seahaven
# Add more mappings...
```

**Result**:
- `bad-deployment` → `bank-of-springfield-{timestamp}`
- `database-lock` → `bank-of-punxsutawney-{timestamp}`
- Unmapped scenarios use default: `{scenario}-scenario-{timestamp}`

### 3. Namespace Override Pattern
**Why**: Scenarios should work in both user namespaces and dedicated scenario namespaces without code duplication.

**How**: Use bash parameter expansion with default values in [scenarios/common.sh:6](scenarios/common.sh#L6).

```bash
NAMESPACE="${NAMESPACE:-anthos-bank-${USER}}"
```

**Usage**:
```bash
# Uses default user namespace
./scenarios/bad-deployment-scenario.sh

# Override to use dedicated namespace
NAMESPACE="bank-of-springfield-20260102-100000" ./scenarios/bad-deployment-scenario.sh
```

### 4. Parallel Execution
**Why**: Deploying 10+ namespaces sequentially takes too long. Running in parallel reduces time from 30+ minutes to ~3 minutes.

**How**: Background processes with PID tracking and exit status files.

**Example from** [inject-all-scenarios.sh:82-101](inject-all-scenarios.sh#L82-L101):
```bash
for scenario in "${existing_namespaces[@]}"; do
    namespace="${scenario}-scenario"
    scenario_script="${SCRIPT_DIR}/scenarios/${scenario}-scenario.sh"

    # Run scenario in background with namespace override
    (
        NAMESPACE="$namespace" "$scenario_script" > "/tmp/${scenario}-injection.log" 2>&1
        echo $? > "/tmp/${scenario}-injection.status"
    ) &

    pids+=($!)
    scenario_names+=("$scenario")
done

# Wait for all processes and collect results
for i in "${!pids[@]}"; do
    wait "${pids[$i]}" 2>/dev/null || true
    # Check exit status from file
    if [ -f "/tmp/${scenario}-injection.status" ]; then
        status=$(cat "/tmp/${scenario}-injection.status")
        # Handle success/failure
    fi
done
```

### 5. Shared Library Pattern
**Why**: DRY principle - eliminate ~150 lines of duplicated code across scripts.

**How**: Extract common functions to [lib/common-helpers.sh](lib/common-helpers.sh) and source from all scripts.

**Usage**:
```bash
# In every multi-namespace script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common-helpers.sh"

# Now use shared functions
print_success "Deployment complete!"
SCENARIOS=($(discover_scenarios "$SCRIPT_DIR"))
namespace_base=$(get_namespace_base "bad-deployment")  # Returns "bank-of-springfield"
```

### 6. Fast Deployment Without Waiting
**Why**: Speed. Waiting for all pods to be ready in 10+ namespaces is unnecessary for initial deployment.

**How**: Remove waiting loops from deployment. Pods start in background. Provide separate status checking script.

**Before** (slow):
```bash
kubectl wait --for=condition=available --timeout=300s deployment -l application=bank-of-anthos -n "$namespace"
```

**After** (fast):
```bash
print_success "Deployment to ${namespace} complete!"
print_info "Pods are starting in the background..."
# No waiting - continue to next namespace immediately
```

Use [check-all-scenarios.sh](check-all-scenarios.sh) separately to verify readiness.

## Development Patterns

### Adding a New Failure Scenario

1. **Create scenario script** in `scenarios/` directory:
   ```bash
   scenarios/new-failure-scenario.sh
   ```

2. **Follow the naming convention**: `*-scenario.sh` (critical for auto-discovery)

3. **Use the common library**:
   ```bash
   #!/bin/bash
   set -euo pipefail

   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   source "${SCRIPT_DIR}/common.sh"

   # Namespace will be overridden when called from setup-all-scenarios.sh
   NAMESPACE="${NAMESPACE:-anthos-bank-${USER}}"

   # Your failure injection logic here
   kubectl patch deployment ... -n "$NAMESPACE"
   ```

4. **No other changes needed** - The scenario will automatically:
   - Appear in `setup-all-scenarios.sh` deployment list
   - Appear in `inject-failure-by-namespace.sh` interactive menu
   - Be included in `inject-all-scenarios.sh` parallel injection
   - Be checked by `check-all-scenarios.sh`
   - Be cleaned up by `cleanup-all-scenarios.sh`

### Testing Changes to Multi-Namespace Scripts

```bash
# Test with a single scenario first
SCENARIOS=("bad-deployment") ./setup-all-scenarios.sh

# Verify discovery works
./lib/common-helpers.sh  # Run discover_scenarios standalone

# Test parallel execution with small subset
# Edit script temporarily to limit scenarios array
```

### Error Handling Standards

All scripts use strict error handling:
```bash
set -euo pipefail
```

- `set -e` - Exit on any command failure
- `set -u` - Exit on undefined variable usage
- `set -o pipefail` - Fail on pipe errors

For operations that may fail but shouldn't stop the script:
```bash
kubectl delete something 2>/dev/null || true
```

### Color Output Standards

Use shared functions from [lib/common-helpers.sh](lib/common-helpers.sh):

```bash
print_info "Informational message"      # Blue
print_success "Success message"          # Green
print_warning "Warning message"          # Yellow
print_error "Error message"              # Red
```

## Repository Structure

```
.
├── CLAUDE.md                           # This file
├── MULTI_NAMESPACE_SETUP.md           # Multi-namespace documentation
├── README.md                           # Main documentation
│
├── bank-of-anthos/                     # Bank of Anthos source
│   ├── helm/                           # Helm charts
│   ├── kubernetes-manifests/          # K8s manifests
│   └── extras/jwt/                     # JWT secrets
│
├── config/
│   └── namespace-mapping.conf         # Scenario → namespace mappings
│
├── lib/
│   └── common-helpers.sh              # Shared utilities
│
├── batch/                              # Multi-namespace batch operations
│   ├── setup-all-scenarios.sh
│   ├── inject-all-scenarios.sh
│   ├── check-all-scenarios.sh
│   └── cleanup-all-scenarios.sh
│
├── scenarios/
│   ├── common.sh                      # Scenario-specific shared code
│   ├── bad-deployment-scenario.sh
│   ├── config-misconfigured-scenario.sh
│   ├── database-lock-scenario.sh
│   ├── helm-bad-upgrade-scenario.sh
│   ├── high-load-scenario.sh
│   ├── limit-range-contacts-scenario.sh
│   ├── network-policy-scenario.sh
│   ├── node-selector-scenario.sh
│   ├── oom-killed-scenario.sh
│   ├── resource-quota-scenario.sh
│   └── restore.sh                     # Restore/cleanup scenario
│
├── setup-bank-of-anthos.sh           # Original user-namespace setup
├── setup-all-scenarios.sh            # Multi-namespace deployment
├── inject-failure.sh                 # Original interactive injection
├── inject-failure-by-namespace.sh    # Multi-namespace interactive injection
├── inject-all-scenarios.sh           # Parallel injection to all namespaces
├── check-all-scenarios.sh            # Status checking
└── cleanup-all-scenarios.sh          # Multi-namespace cleanup
```

## Important Files Reference

- **[lib/common-helpers.sh](lib/common-helpers.sh)** - Core shared utilities (includes `get_namespace_base()`)
- **[config/namespace-mapping.conf](config/namespace-mapping.conf)** - Scenario to namespace mappings
- **[scenarios/common.sh](scenarios/common.sh)** - Scenario-specific shared code
- **[MULTI_NAMESPACE_SETUP.md](MULTI_NAMESPACE_SETUP.md)** - Detailed multi-namespace guide
- **[batch/setup-all-scenarios.sh](batch/setup-all-scenarios.sh)** - Main deployment script
- **[batch/inject-all-scenarios.sh](batch/inject-all-scenarios.sh)** - Parallel failure injection

## Tips for Future Development

1. **Always test namespace override**: Verify scenarios work in both user and dedicated namespaces
2. **Use dynamic discovery**: Never hardcode scenario lists
3. **Keep it fast**: Avoid unnecessary waiting unless explicitly required
4. **Follow naming conventions**: `*-scenario.sh` pattern is critical
5. **Document in MULTI_NAMESPACE_SETUP.md**: Keep usage examples up to date
6. **Use shared functions**: Don't duplicate color output or discovery logic
7. **Test parallel execution**: Ensure scenarios don't interfere with each other
8. **Bash 3.x compatibility**: Test on macOS (`/bin/bash`) - no associative arrays, avoid bash 4+ features
9. **Update namespace mapping**: Add new scenarios to [config/namespace-mapping.conf](config/namespace-mapping.conf) with creative names

## Common Troubleshooting

### Scenario not appearing in scripts
- Check filename matches `*-scenario.sh` pattern
- Verify file is executable: `chmod +x scenarios/your-scenario.sh`
- Run discovery manually: `bash -c 'source lib/common-helpers.sh && discover_scenarios .'`

### Namespace deployment hanging
- Don't wait for pods in deployment scripts - let them start in background
- Use `check-all-scenarios.sh` to monitor readiness
- Check individual namespace: `kubectl get pods -n <namespace> -w`

### Parallel injection failures
- Check logs in `/tmp/<scenario>-injection.log`
- Verify namespace exists before injection
- Run single scenario first to debug: `NAMESPACE="test-scenario" ./scenarios/bad-deployment-scenario.sh`

## Git Workflow

Current branch: **master** (also the main branch for PRs)

Untracked files: `control-status-server.sh`

Recent commits show continuous enhancement of deployment readiness checks and resource management features.

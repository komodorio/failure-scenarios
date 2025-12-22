# Batch Operations Scripts

This directory contains all scripts for batch operations on Bank of Anthos deployments across multiple scenario-specific namespaces.

## Quick Start

Instead of running these scripts directly, use the main entry point:

```bash
cd ..
./start.sh
```

## Available Scripts

### Setup & Deployment
- **setup-all-scenarios.sh** - Deploy Bank of Anthos to all scenario namespaces (parallel, ~30-45 sec)
- **check-all-scenarios.sh** - Check status of all scenario namespaces

### Failure Injection
- **inject-all-scenarios.sh** - Inject failures in all namespaces (parallel, ~1-2 min)
- **inject-failure-by-namespace.sh** - Inject failure in specific namespace (interactive)

### Restoration
- **restore-all-scenarios.sh** - Restore all namespaces to normal state (parallel, ~1-2 min)
- **restore-by-namespace.sh** - Restore specific namespace (interactive)

### Cleanup
- **cleanup-all-scenarios.sh** - Delete all scenario namespaces (parallel force delete, ~30-60 sec)

## Direct Usage

All scripts can be run directly from this directory:

```bash
# Setup
./setup-all-scenarios.sh

# Inject
./inject-all-scenarios.sh

# Check
./check-all-scenarios.sh

# Restore
./restore-all-scenarios.sh

# Cleanup
./cleanup-all-scenarios.sh
```

## Features

- **Dynamic Discovery** - Automatically discovers scenarios from `../scenarios/` directory
- **Parallel Execution** - All batch operations run in parallel for maximum speed
- **Shared Library** - Uses `../lib/common-helpers.sh` for consistent UX
- **Interactive Menus** - User-friendly scenario and namespace selection
- **Error Handling** - Detailed success/failure reporting with logs

## Documentation

See [../MULTI_NAMESPACE_SETUP.md](../MULTI_NAMESPACE_SETUP.md) for complete documentation.

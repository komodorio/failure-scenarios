# Bank of Anthos Failure Scenarios Failure Injection System

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.30+-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)

> A comprehensive Kubernetes failure injection and testing framework for Bank of Anthos, enabling automated chaos engineering and resilience testing across isolated namespaces.

## 🚀 Quick Start

Get up and running in under 5 minutes:

```bash
# Clone the repository
git clone git@github.com:komodorio/failure-scenarios.git
cd failure-scenarios

# Launch the interactive menu
./start.sh
```

Or run individual commands:

```bash
# Deploy all scenarios to isolated namespaces (~3 min)
./batch/setup-all-scenarios.sh

# Check deployment status
./batch/check-all-scenarios.sh

# Inject all failures in parallel (~1-2 min)
./batch/inject-all-scenarios.sh

# Cleanup all namespaces
./batch/cleanup-all-scenarios.sh
```

## ✨ Features

- 🎯 **14 Failure Scenarios** - Database locks, OOM kills, policy violations, CronJob failures, and more
- ⚡ **Parallel Execution** - Deploy 14 namespaces in parallel (~3 minutes)
- 🔒 **Isolated Testing** - Each scenario runs in its own namespace
- 🔄 **Dynamic Discovery** - Add new scenarios with zero code changes
- 📊 **Multiple Interfaces** - Interactive menus, individual commands, or batch operations
- 🛠️ **Self-Contained Scenarios** - Each scenario can inject and revert its own failures independently
- ♻️ **Restore & Cleanup** - Built-in restoration scripts to return to normal state

## 📋 Prerequisites

Before running this project, ensure you have:

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| **Kubernetes cluster** | 1.19+ | Target environment for failure injection |
| **kubectl** | 1.30+ | Kubernetes CLI tool |
| **helm** | 3.0+ | Package manager for Kubernetes |
| **jq** | 1.6+ | JSON processor for parsing |
| **bash** | 4.0+ | Shell interpreter |

### Cluster Resources

- **Minimum:** 5 CPU cores, 5GB RAM, 50GB storage

### Installation

```bash
# macOS
brew install kubectl helm jq

# Ubuntu/Debian
sudo apt-get install kubectl helm jq

# Check versions
kubectl version --client
helm version --short
jq --version
```

## 📖 Available Failure Scenarios

For a full summary of all available failure scenarios, see the [Scenarios Overview Table](./scenarios/SCENARIOS.md).


## 🎮 Usage

### Interactive Menu (Recommended)

```bash
./start.sh
```

Provides a menu-driven interface with options:
1. Setup All Scenarios
2. Check All Scenarios
3. Inject All Scenarios
4. Inject by Namespace (interactive)
5. Restore All Scenarios
6. Restore by Namespace (interactive)
7. Cleanup All Scenarios

### Individual Scenario Testing

Each scenario is self-contained with inject and revert capabilities:

```bash
# Inject failure (default action)
./scenarios/bad-deployment-scenario.sh
./scenarios/bad-deployment-scenario.sh inject

# Revert failure
./scenarios/bad-deployment-scenario.sh revert

# With specific namespace
NAMESPACE="bad-deployment-scenario" ./scenarios/bad-deployment-scenario.sh inject
NAMESPACE="bad-deployment-scenario" ./scenarios/bad-deployment-scenario.sh revert

# Check status
kubectl get pods -n bad-deployment-scenario -w
```

### Batch Operations

```bash
# Setup all scenarios in parallel
./batch/setup-all-scenarios.sh

# Inject all failures in parallel
./batch/inject-all-scenarios.sh

# Restore all scenarios
./batch/restore-all-scenarios.sh

# Check status of all scenarios
./batch/check-all-scenarios.sh
```

## 📚 Documentation

- **[Architecture & Design](CLAUDE.md)** - In-depth architectural decisions and patterns
- **[Multi-Namespace Setup](MULTI_NAMESPACE_SETUP.md)** - Complete guide to multi-namespace workflows
- **[Scenario Details](scenarios/README.md)** - Individual scenario documentation
- **[Security Policy](SECURITY.md)** - Security best practices and vulnerability reporting

## 🏗️ Architecture

This system follows a modular, extensible architecture:

```
├── batch/                    # Batch operations for all scenarios
├── scenarios/                # Individual failure injection scripts
├── lib/                      # Shared utilities and helpers
├── config/                   # Configuration files
│   └── namespace-mapping.conf  # Maps scenarios to custom namespaces
└── bank-of-anthos/          # Google Cloud sample application
```

### Key Design Patterns

1. **Dynamic Scenario Discovery** - Automatically discovers `*-scenario.sh` files
2. **Custom Namespace Mapping** - Scenarios deploy to creative movie-themed namespaces
3. **Namespace Override** - Same scripts work for user and dedicated namespaces
4. **Parallel Execution** - Background processes with PID tracking
5. **Shared Libraries** - DRY principle with centralized utilities

### Namespace Naming

Each scenario deploys to a custom namespace inspired by fictional cities from movies:
- `bad-deployment` → `bank-of-springfield` (The Simpsons Movie)
- `database-lock` → `bank-of-punxsutawney` (Groundhog Day)
- `high-load` → `bank-of-seahaven` (The Truman Show)
- And more! See [config/namespace-mapping.conf](config/namespace-mapping.conf) for the complete list.

All namespaces include a timestamp suffix for isolation: `bank-of-springfield-{timestamp}`


### Adding a New Scenario

1. Create `scenarios/your-failure-scenario.sh`
2. Follow the `*-scenario.sh` naming convention
3. Implement both `inject_failure()` and `revert_failure()` functions
4. Use the template from `scenarios/README.md`
5. Test both actions:
   ```bash
   ./scenarios/your-failure-scenario.sh inject
   ./scenarios/your-failure-scenario.sh revert
   ```
6. Submit a pull request

No other code changes needed - scenarios are auto-discovered and automatically integrated!

## 📊 Example Output

```bash
$ ./batch/setup-all-scenarios.sh

========================================
  Multi-Namespace Scenario Setup
========================================

Deploying Bank of Anthos to 14 scenario namespaces in parallel...

✓ bad-deployment-scenario deployed (12.3s)
✓ config-misconfigured-scenario deployed (11.8s)
✓ database-lock-scenario deployed (13.1s)
✓ failed-backup-cronjob-scenario deployed (12.0s)
✓ helm-bad-upgrade-scenario deployed (12.7s)
✓ high-load-scenario deployed (11.5s)
✓ kyverno-policy-scenario deployed (14.2s)
✓ limit-range-contacts-scenario deployed (12.9s)
✓ missing-storage-class-scenario deployed (12.4s)
✓ network-policy-scenario deployed (12.1s)
✓ node-selector-scenario deployed (11.9s)
✓ oom-killed-scenario deployed (13.4s)
✓ resource-quota-scenario deployed (12.2s)
✓ wrong-sa-scenario deployed (11.7s)

[SUCCESS] All 14 scenarios deployed successfully!
Total time: 3m 18s
```

## ⏱️ Performance Metrics

| Operation | Time | Notes |
|-----------|------|-------|
| Setup all scenarios | ~3 min | 10+ namespaces in parallel (depends on the number of scenarios) |
| Inject all scenarios | ~1-2 min | Parallel failure injection |
| Check all scenarios | ~10 sec | Quick status overview |
| Cleanup all scenarios | ~2 min | Parallel namespace deletion |

## 🔒 Security

This tool intentionally causes failures in Kubernetes clusters. Please review our [Security Policy](SECURITY.md) for:

- Vulnerability reporting
- Best practices
- Known security considerations

**⚠️ Important:** Only use on dedicated test clusters. **Never run on production.**

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built on [Bank of Anthos](https://github.com/GoogleCloudPlatform/bank-of-anthos) by Google Cloud
- Inspired by chaos engineering principles from [Chaos Monkey](https://netflix.github.io/chaosmonkey/)

## 📞 Support

- **Issues:** [GitHub Issues](https://github.com/komodorio/failure-scenarios/issues)
- **Security:** security@komodor.io
- **Documentation:** See [docs](#-documentation) section above

---

Made with ❤️ by [Komodor](https://komodor.com)

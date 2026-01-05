# Security Policy

## Supported Versions

Currently supported versions for security updates:

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue, please follow these steps:

1. **DO NOT** open a public GitHub issue
2. Email security details to: security@komodor.io
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

### What to expect

- **Response time:** We'll acknowledge within 48 hours
- **Updates:** We'll keep you informed of progress
- **Credit:** We'll credit you in release notes (unless you prefer anonymity)

## Security Best Practices

When using this tool:

- **Use dedicated test clusters** - Never run failure injection scenarios on production clusters
- **Review scenario scripts** - Examine what each scenario does before execution
- **Limit RBAC permissions** - Grant only necessary namespace access
- **Monitor resource consumption** - Scenarios can consume significant cluster resources
- **Isolate namespaces** - Use the multi-namespace approach to prevent cross-contamination
- **Clean up after testing** - Use cleanup scripts to remove test namespaces

## Known Security Considerations

### Failure Injection Risks

This tool is designed to intentionally cause failures in Kubernetes clusters. Be aware:

- **Resource exhaustion** - High-load and OOM scenarios consume CPU/memory
- **Database locks** - Database-lock scenario can affect application state
- **Network disruption** - Network policy scenarios block traffic
- **Data loss potential** - Always test on non-production data

### Access Control

- Requires cluster-admin or equivalent permissions to create/modify namespaces
- Can modify deployments, services, and other Kubernetes resources
- Should only be used by authorized operators

## Disclosure Policy

- Security issues are addressed in priority order
- Fixes are released as patch versions
- Public disclosure after fix is available (coordinated disclosure)
- Security advisories published through GitHub Security Advisories

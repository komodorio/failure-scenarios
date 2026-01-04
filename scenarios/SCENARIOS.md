# Failure Scenarios Summary

This document provides a summary of all available failure scenarios, their affected services, and self-healing actions.

## Scenarios Overview Table

| Scenario Name | Namespace | Affected Service(s) | Self-Healing | Self-Healing Action |
|---------------|-----------|---------------------|--------------|---------------------|
| **bad-deployment** | bank-of-springfield | ledgerwriter | ✅ Yes | Rollback to previous image version |
| **config-misconfigured** | bank-of-hill-valley | ledgerwriter | ❌ No | Manual ConfigMap fix required |
| **database-lock** | bank-of-punxsutawney | ledger-db, ledgerwriter, balancereader, transactionhistory, frontend | ❌ No | Manual lock release required |
| **failed-backup-cronjob** | bank-of-arendelle | ledger-db-backup (CronJob) | ❌ No | Manual CronJob schedule fix required |
| **helm-bad-upgrade** | bank-of-bedford-falls | cash-cache (Redis) | ✅ Yes | Helm rollback |
| **high-load** | bank-of-seahaven | loadgenerator, users, frontend | ❌ No | Manual load reduction required |
| **kyverno-policy** | bank-of-koriko | contacts | ❌ No | Manual policy removal or pod annotation required |
| **limit-range-contacts** | bank-of-sandford | contacts | ❌ No | Manual LimitRange removal required |
| **missing-storage-class** | bank-of-mos-eisley | accounts-db (StatefulSet) | ❌ No | Manual StorageClass creation or PVC fix required |
| **network-policy** | bank-of-twin-peaks | accounts-db, userservice, frontend | ❌ No | Manual NetworkPolicy removal required |
| **node-selector** | bank-of-pleasantville | balancereader | ✅ Yes | Rollback (remove nodeSelector) |
| **oom-killed** | bank-of-radiator-springs | transactionhistory | ✅ Yes | Rollback to original memory limits |
| **resource-quota** | bank-of-whoville | userservice, all deployments | ❌ No | Manual ResourceQuota removal required |
| **wrong-sa** | bank-of-hogsmeade | ledgerwriter | ❌ No | Manual ServiceAccount fix required |

-------
</br>

## Adding New Scenarios

When adding a new scenario to this repository:

1. Create the scenario script: `scenarios/your-scenario-name-scenario.sh`
2. Add namespace mapping to: [config/namespace-mapping.conf](../config/namespace-mapping.conf)
3. Update this table with the new scenario details
4. Document whether it supports self-healing
5. Test both inject and revert actions

## See Also

- [Individual Scenario Documentation](README.md) - Detailed documentation for each scenario
- [Multi-Namespace Setup](../MULTI_NAMESPACE_SETUP.md) - Complete guide to multi-namespace workflows
- [Architecture Overview](../CLAUDE.md) - Technical architecture and design decisions

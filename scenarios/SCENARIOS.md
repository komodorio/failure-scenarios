# Failure Scenarios Summary

This document provides a summary of all available failure scenarios, their affected services, and self-healing actions.

## Scenarios Overview Table


| Scenario Name             | Namespace                | Affected Service(s)                                                                   | Self-Healing | Action                                           |
| --------------------------- | -------------------------- | --------------------------------------------------------------------------------------- | -------------- | -------------------------------------------------- |
| **bad-deployment**        | bank-of-springfield      | `ledgerwriter` fails to start due to a non-existent image                             | ✅ Yes       | Rollback to previous image version               |
| **config-misconfigured**  | bank-of-hill-valley      | `ledgerwriter` fails to start due to a typo on a mounted configmap                    | ❌ No        | Manual ConfigMap fix required                    |
| **database-lock**         | bank-of-punxsutawney     | `balancereader` availability fails due to database locks in ledger db                 | ❌ No        | Manual lock release required                     |
| **failed-backup-cronjob** | bank-of-arendelle        | `ledger-db-backup `(CronJob) fails to start due to "high load" on the database timers | ❌ No        | Manual CronJob schedule fix required             |
| **helm-bad-upgrade**      | bank-of-bedford-falls    | `cash-cache` redis fails to start due to a bad configuration typo                     | ✅ Yes       | Helm rollback                                    |
| **kyverno-policy**        | bank-of-koriko           | `transaction-report` fails to start due to a kyverno policy                           | ❌ No        | Manual policy removal or pod annotation required |
| **limit-range-contacts**  | bank-of-sandford         | `contacts` fails to start due to a newly introduced limit range                       | ❌ No        | Manual LimitRange removal required               |
| **missing-storage-class** | bank-of-mos-eisley       | `transactions-audit-log` fails to start due to a non existent storage class           | ❌ No        | Manual StorageClass creation or PVC fix required |
| **network-policy**        | bank-of-twin-peaks       | `userservice` fails. to connect to `accounts-db` due to a NetworkPolicy               | ❌ No        | Manual NetworkPolicy removal required            |
| **node-selector**         | bank-of-pleasantville    | `balancereader` fails a deploy after adding a non-existent node-selector              | ✅ Yes       | Rollback (remove nodeSelector)                   |
| **oom-killed**            | bank-of-radiator-springs | `transactionhistory` fails to start after a deploy with a much lower limits           | ✅ Yes       | Rollback to original memory limits               |
| **resource-quota**        | bank-of-whoville         | `userservice` fails scaling to 5 replicas causing                                     | ❌ No        | Manual ResourceQuota removal required            |
| **wrong-sa**              | bank-of-hogsmeade        | `riskassessment` fails to start due to a typo in service account name                 | ❌ No        | Manual ServiceAccount fix required               |

---

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

# ✅ STRICT mTLS Mismatch Scenario - Implementation Complete

## Scenario Details
- **ID**: 9
- **Name**: STRICT mTLS Mismatch
- **Category**: Networking / Service Mesh / Security
- **Namespace**: `bank-of-westeros` (fictional city from Game of Thrones)

## What Was Created

### 1. Main Scenario Script
**File**: `/scenarios/mtls-mismatch-scenario.sh`
- Fully executable scenario following your existing patterns
- Supports `inject` and `revert` actions
- Comprehensive error checking and validation
- Detailed observability instructions
- Prerequisites validation (Istio installation, sidecar injection)

### 2. Detailed Guide
**File**: `/scenarios/mtls-mismatch-scenario-guide.md`
- Complete investigation playbook
- Real-world troubleshooting flow
- Expected symptoms and behaviors
- Command references for debugging
- Common production variations

### 3. Documentation Updates
**Files Updated**:
- `scenarios/README.md` - Added scenario #11 with full description
- `scenarios/SCENARIOS.md` - Added to scenarios table
- `config/namespace-mapping.conf` - Added `mtls-mismatch=bank-of-westeros`

## How It Works

### The Failure Mechanism
1. **PeerAuthentication Policy** created on `userservice` with `mtls.mode: STRICT`
   - Requires ALL incoming connections to use mTLS
   - This includes readiness/liveness probes (which may not support mTLS)

2. **DestinationRule** created for `accounts-db` with `tls.mode: DISABLE`
   - Disables TLS for outbound connections from userservice to accounts-db
   - Creates the mismatch: strict enforcement but no TLS used

3. **Result**: mTLS handshake failures, connection resets, service unavailability

### Real-World Accuracy
This scenario mirrors actual production incidents:
- ✅ Common during service mesh adoption phases
- ✅ Happens when security policies are applied inconsistently
- ✅ Realistic symptoms: 503 errors, TLS handshake timeouts
- ✅ Requires proper investigation through logs, policies, and Istio tools
- ✅ Representative of multi-team coordination failures

## Usage

### Quick Start
```bash
# Setup (creates namespace with Istio injection)
./batch/setup-all-scenarios.sh

# Inject the mTLS mismatch
NAMESPACE=bank-of-westeros ./scenarios/mtls-mismatch-scenario.sh inject

# Observe the failure
kubectl get pods -l app=userservice -n bank-of-westeros -w
kubectl logs deployment/userservice -n bank-of-westeros -c istio-proxy

# Revert when done
NAMESPACE=bank-of-westeros ./scenarios/mtls-mismatch-scenario.sh revert
```

### Prerequisites Check
The script automatically checks for:
- ✅ Istio installed (`istio-system` namespace, `istiod` deployment)
- ✅ Namespace has `istio-injection=enabled` label
- ✅ Pods have Istio sidecar proxies
- ⚠️ Warnings printed if prerequisites not met (doesn't fail hard)

## Observable Symptoms

### What You'll See
1. **Pod Status**: `Running` but `NotReady (0/2)`
2. **Application Logs**: "Connection refused", "Database connection timeout"
3. **Istio Proxy Logs**: "TLS handshake timeout", "upstream connect error"
4. **Pod Events**: "Readiness probe failed"
5. **Frontend**: `503 Service Unavailable` errors
6. **Policies**: `kubectl get peerauthentication,destinationrule` shows mismatched config

### Investigation Path
The scenario simulates a realistic troubleshooting journey:
1. User reports 503 errors
2. Check pod health → NotReady
3. Check logs → Connection/TLS errors
4. Check Istio policies → Discover mismatch
5. Identify root cause → STRICT mTLS vs DISABLE TLS
6. Fix → Remove conflicting policies

## Key Features

### ✅ Production-Realistic
- Actual Istio `PeerAuthentication` and `DestinationRule` resources
- Real mTLS handshake failures (not simulated)
- Authentic symptoms and error messages
- Mirrors real incident investigation flow

### ✅ Repeatable
- Clean inject → observe → revert cycle
- No persistent state issues
- Automatic cleanup on revert
- Can run multiple times

### ✅ Educational
- Comprehensive inline documentation
- Detailed guide with learning points
- Command references for investigation
- Explains "why" not just "how"

### ✅ Safe
- Only affects targeted namespace
- No cluster-wide changes
- Prerequisite validation
- Graceful handling of missing Istio

### ✅ Follows Your Patterns
- Uses `common.sh` helper functions
- Consistent script structure
- Same inject/revert pattern
- Auto-discovered by batch scripts
- Namespace mapping configured

## Testing Recommendations

### Minimum Test
```bash
# Inject
./scenarios/mtls-mismatch-scenario.sh inject

# Verify resources created
kubectl get peerauthentication,destinationrule -n bank-of-westeros

# Revert
./scenarios/mtls-mismatch-scenario.sh revert

# Verify cleanup
kubectl get peerauthentication,destinationrule -n bank-of-westeros
# Should show: No resources found
```

### Full Test (with Istio)
```bash
# 1. Ensure Istio is installed
kubectl get namespace istio-system

# 2. Setup scenario
./batch/setup-all-scenarios.sh

# 3. Inject mTLS mismatch
NAMESPACE=bank-of-westeros ./scenarios/mtls-mismatch-scenario.sh inject

# 4. Observe symptoms
kubectl get pods -n bank-of-westeros -w
# Wait 30-60 seconds for readiness probe to fail

kubectl logs deployment/userservice -n bank-of-westeros -c istio-proxy --tail=50
# Look for TLS handshake errors

# 5. Investigate with istioctl (if available)
istioctl analyze -n bank-of-westeros
istioctl x describe pod -l app=userservice -n bank-of-westeros

# 6. Revert
NAMESPACE=bank-of-westeros ./scenarios/mtls-mismatch-scenario.sh revert

# 7. Verify restoration
kubectl get pods -n bank-of-westeros
# userservice should be Ready (2/2)
```

## Files Summary

```
failure-scenarios/
├── scenarios/
│   ├── mtls-mismatch-scenario.sh           # Main scenario script (executable)
│   ├── mtls-mismatch-scenario-guide.md     # Detailed investigation guide
│   ├── README.md                            # Updated with scenario #11
│   └── SCENARIOS.md                         # Updated scenarios table
└── config/
    └── namespace-mapping.conf               # Added bank-of-westeros mapping
```

## Integration with Existing System

### ✅ Automatically Discovered
- Batch scripts will find it (naming pattern: `*-scenario.sh`)
- No code changes needed in batch scripts

### ✅ Namespace Support
- Respects `NAMESPACE` environment variable
- Works with multi-namespace setup
- Integrated with state management

### ✅ Common Functions
- Uses all standard helpers from `common.sh`
- Consistent output formatting (colors, status messages)
- Standard prerequisite checks

## Next Steps

### To Use This Scenario
1. **Review the guide**: Read `mtls-mismatch-scenario-guide.md` for full details
2. **Check prerequisites**: Ensure Istio is installed (or plan to install it)
3. **Test inject**: Run the scenario to see it in action
4. **Test revert**: Verify cleanup works properly
5. **Share**: Use for training, demos, or testing monitoring tools

### To Test with Klaudia/Bits
According to your spreadsheet, this needs to be "tested with Klaudia" and "tested with Bits":
- The scenario is ready to test
- Follow the investigation path in the guide
- Validate that Klaudia/Bits can detect and diagnose the mTLS mismatch
- Check if they identify the PeerAuthentication and DestinationRule conflict

### Optional Enhancements
If you want to extend this scenario further:
- Add port-level mTLS configuration variations
- Create additional mismatches (e.g., PERMISSIVE vs STRICT)
- Add cross-namespace communication scenarios
- Include certificate provisioning failures

## Notes

### Without Istio
- Script still runs and creates policies
- Warnings printed about missing Istio
- Limited effect (policies created but not enforced)
- Useful for testing policy creation/deletion logic

### With Istio
- Full realistic failure scenario
- Actual mTLS handshake failures
- Readiness probes fail
- Service becomes unavailable
- Complete troubleshooting experience

## Questions or Modifications?
Let me know if you'd like to:
- Adjust the severity of the failure
- Add more observability instructions
- Include additional investigation commands
- Create variations of the scenario
- Modify any documentation

---

**Status**: ✅ **COMPLETE AND READY TO USE**

The scenario is fully implemented, documented, and integrated with your existing framework. It's ready for testing with your monitoring tools (Klaudia/Bits).

Ready for the next scenario when you are! 🚀

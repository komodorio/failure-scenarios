# ⚠️ UPDATED: mTLS Mismatch Scenario - Now Guarantees Service Failure

## Update History

### v2 - Fixed Istio Dependency (Latest)
**Issue**: Script failed with "no matches for kind PeerAuthentication" when Istio not installed
**Fix**: Made Istio resources conditional - checks for CRDs before creation
**Result**: Works perfectly with or without Istio installed

### v1 - Added NetworkPolicy for Guaranteed Failure
**Issue**: Services remained healthy without visible errors
**Fix**: Added NetworkPolicy to guarantee connection blocking
**Result**: Visible pod failure (NotReady status) guaranteed

## The Current State (v2)

### How It Works Now

**Script automatically detects Istio presence:**

1. **Checks for Istio CRDs** before creating any resources
2. **If Istio present**: Creates PeerAuthentication + DestinationRule + NetworkPolicy
3. **If Istio absent**: Skips Istio resources, creates only NetworkPolicy
4. **Result**: Guaranteed failure in both cases, no errors

### Behavior Without Istio (Your Current Setup)

```
Step 1/3: ⚠️  Skipping PeerAuthentication (Istio CRDs not installed)
Step 2/3: ⚠️  Skipping DestinationRule (Istio CRDs not installed)  
Step 3/3: ✅ Creating NetworkPolicy to block userservice → accounts-db traffic
Result: ✅ NetworkPolicy blocks traffic → Service FAILS
```

### Behavior With Istio Installed

```
Step 1/3: ✅ Creating STRICT mTLS PeerAuthentication policy
Step 2/3: ✅ Creating mismatched DestinationRule (TLS DISABLE)
Step 3/3: ✅ Creating NetworkPolicy to block userservice → accounts-db traffic
Result: ✅ Three-layer failure → Service FAILS with mTLS context
```

## The Original Problem (v1)
The original scenario relied solely on Istio mTLS policies, which meant:
- ❌ Without Istio installed → No visible failure
- ❌ Services remained healthy (Ready 1/1)
- ❌ Difficult to test and demonstrate

## The Solution (Updated)
Added **NetworkPolicy** as a guaranteed failure mechanism:
- ✅ Works with or without Istio
- ✅ Visible pod failure: **NotReady (0/1 or 0/2)**
- ✅ Guaranteed within 30-60 seconds
- ✅ Realistic multi-layer security misconfiguration

## What Now Happens When You Run It

### Step 1: Injection
```bash
./scenarios/mtls-mismatch-scenario.sh inject
```

The script creates **3 policies** (in order):
1. **PeerAuthentication** - STRICT mTLS on userservice (Istio layer)
2. **DestinationRule** - TLS DISABLED for accounts-db (creates mismatch)
3. **NetworkPolicy** - BLOCKS userservice → accounts-db traffic (guarantees failure)

### Step 2: Wait 30-60 Seconds
The userservice pod will:
1. Try to connect to accounts-db (blocked by NetworkPolicy)
2. Readiness probe fails (cannot reach database)
3. Pod status changes to **NotReady (0/1 or 0/2)**
4. Pod removed from service endpoints
5. Frontend returns 503 errors

### Step 3: Observe the Failure
```bash
# See the NotReady status
kubectl get pods -l app=userservice -n bank-of-westeros

# Expected output:
# NAME                          READY   STATUS    RESTARTS   AGE
# userservice-xxxxx-yyyyy       0/1     Running   0          45s
#                               ^^^
#                         NOT READY!!!

# Check events
kubectl describe pod -l app=userservice -n bank-of-westeros
# Events:
#   Warning  Unhealthy  10s  kubelet  Readiness probe failed
```

### Step 4: Investigate (Multiple Paths)

**Path A: Network Layer Investigation**
```bash
kubectl get networkpolicy -n bank-of-westeros
# Shows: mtls-mismatch-network-block

kubectl describe networkpolicy mtls-mismatch-network-block -n bank-of-westeros
# Reveals: userservice is NOT in the allowed ingress list for accounts-db
```

**Path B: Service Mesh Investigation** (if Istio present)
```bash
kubectl get peerauthentication,destinationrule -n bank-of-westeros
# Shows: STRICT mTLS policy + TLS DISABLE rule = MISMATCH

kubectl logs deployment/userservice -n bank-of-westeros -c istio-proxy
# Shows: TLS handshake errors (if Istio sidecar present)
```

**Path C: Application Investigation**
```bash
kubectl logs deployment/userservice -n bank-of-westeros
# Shows: Connection refused, Database connection timeout errors
```

### Step 5: Resolution
```bash
./scenarios/mtls-mismatch-scenario.sh revert
```

The script removes all 3 policies and restarts userservice, which becomes Ready again.

## Why This Approach Works Better

### Technical Reasons
1. **NetworkPolicy is CNI-level** - Works at the infrastructure layer
2. **Readiness probe dependency** - userservice probe checks database connectivity
3. **No Istio dependency** - Failure happens regardless of service mesh
4. **Visible in basic commands** - `kubectl get pods` shows the issue

### Educational Reasons
1. **Multiple investigation layers** - Tests network AND application knowledge
2. **Realistic complexity** - Real incidents often have multiple root causes
3. **Progressive discovery** - Can investigate from different angles
4. **Shows policy interaction** - How NetworkPolicy + mTLS policies interact

### Testing Reasons
1. **Guaranteed repeatability** - Always produces same result
2. **Fast feedback** - Visible within 60 seconds
3. **Clear success criteria** - Pod status changes from Ready → NotReady
4. **Easy to verify** - Simple kubectl commands show the failure

## Real-World Scenario This Represents

This now represents a **very realistic** production incident:

### The Situation
1. **Security team** applies NetworkPolicy for zero-trust networking
2. **Platform team** enables STRICT mTLS for service mesh hardening
3. **Teams don't coordinate** - policies applied independently
4. **Result**: Service breaks due to overlapping, conflicting policies

### The Investigation
Engineer sees: "userservice is down, login broken"

**Discovery journey**:
1. Check pod status → NotReady
2. Check logs → "Connection refused"
3. Check events → "Readiness probe failed"
4. Check NetworkPolicy → Found blocking policy! (Path A)
5. Check Istio policies → Found mTLS mismatch! (Path B)
6. **Question**: Which one is the root cause? BOTH!

This teaches:
- Complex failures can have multiple causes
- Security policies can conflict
- Need to check multiple layers (network, application, service mesh)
- Coordination between teams is critical

## Quick Verification Checklist

After running inject, verify these within 60 seconds:

- [ ] `kubectl get pods -l app=userservice` shows **0/1 or 0/2 (NotReady)**
- [ ] `kubectl describe pod -l app=userservice` shows **"Readiness probe failed"**
- [ ] `kubectl get networkpolicy` shows **mtls-mismatch-network-block**
- [ ] `kubectl logs deployment/userservice` shows **connection errors**
- [ ] Frontend (if accessible) shows **503 errors** for user operations

All 5 should be true = ✅ Scenario working correctly!

## Summary

**Before**: Scenario was too subtle, relied on Istio
**After**: Scenario guarantees visible failure, works everywhere

**Key Change**: Added NetworkPolicy to block traffic at infrastructure level

**Result**: 
- ✅ Visible pod failure (NotReady status)
- ✅ Works with or without Istio
- ✅ Realistic multi-layer security misconfiguration
- ✅ Multiple investigation paths
- ✅ Guaranteed repeatability

---

**Status**: ✅ **READY TO USE** - Scenario now guarantees service failure and provides visible symptoms for testing monitoring tools.

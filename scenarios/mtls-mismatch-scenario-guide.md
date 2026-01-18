# STRICT mTLS Mismatch Scenario - Quick Reference

## Scenario ID: 9

## Overview
Simulates a realistic Istio service mesh misconfiguration where **STRICT mTLS** is enforced on one service (userservice) but the communication to another service (accounts-db) has TLS disabled via DestinationRule, causing mTLS handshake failures and service-to-service communication breakdown.

## Real-World Context
This scenario represents common production incidents during:
- **Gradual service mesh adoption** (some services with mTLS, others without)
- **Security policy rollouts** (security team enforces STRICT without coordination)
- **Configuration drift** (PeerAuthentication and DestinationRule mismatch)
- **Multi-team environments** (different teams managing different services inconsistently)

## Root Cause
**STRICT mTLS enforced on userservice only**, but connections to accounts-db attempt non-mTLS communication due to `DestinationRule` with `tls.mode: DISABLE`, causing handshake failures.

## Prerequisites

### Required
- Kubernetes cluster
- Bank of Anthos deployed
- Istio service mesh installed (`istiod` running in `istio-system` namespace)
- Namespace labeled with `istio-injection=enabled`
- Pods must have Istio sidecar proxies (2+ containers per pod)

### Installation Check
```bash
# Check if Istio is installed
kubectl get namespace istio-system
kubectl get deployment istiod -n istio-system

# Check namespace labeling
kubectl get namespace bank-of-westeros -o jsonpath='{.metadata.labels.istio-injection}'
# Should output: enabled

# Check for sidecar injection
kubectl get pods -n bank-of-westeros -l app=userservice -o jsonpath='{.items[0].spec.containers[*].name}'
# Should show: userservice istio-proxy
```

### Enable Istio Injection (if needed)
```bash
# Label the namespace
kubectl label namespace bank-of-westeros istio-injection=enabled

# Restart pods to inject sidecar
kubectl rollout restart deployment -n bank-of-westeros
```

## Usage

### Inject Failure
```bash
# Using batch setup (recommended - creates namespace with Istio injection)
./batch/setup-all-scenarios.sh

# Or inject to existing namespace
NAMESPACE=bank-of-westeros ./scenarios/mtls-mismatch-scenario.sh inject
```

### Symptoms to Observe

**1. Pod Status Issues**
```bash
kubectl get pods -l app=userservice -n bank-of-westeros -w
# Expected: Running but NotReady (0/2) - probe failures
```

**2. Application Logs (Database Connection Errors)**
```bash
kubectl logs -f deployment/userservice -n bank-of-westeros -c userservice
# Look for:
# - "Connection refused"
# - "Connection reset by peer"
# - "Database connection timeout"
```

**3. Istio Proxy Logs (TLS Handshake Failures)**
```bash
kubectl logs -f deployment/userservice -n bank-of-westeros -c istio-proxy
# Look for:
# - "TLS handshake timeout"
# - "upstream connect error"
# - "TLS error: Secret is not supplied by SDS"
# - "401 Unauthorized"
```

**4. Pod Events (Readiness Probe Failures)**
```bash
kubectl describe pod -l app=userservice -n bank-of-westeros
# Events section shows:
# - "Readiness probe failed"
# - "Liveness probe succeeded, but readiness failed"
```

**5. Istio Configuration**
```bash
# List mTLS policies
kubectl get peerauthentication -n bank-of-westeros
kubectl get destinationrule -n bank-of-westeros

# Detailed policy inspection
kubectl get peerauthentication userservice-strict-mtls -n bank-of-westeros -o yaml
kubectl get destinationrule accounts-db-mtls -n bank-of-westeros -o yaml
```

**6. Istio Analysis (if `istioctl` available)**
```bash
# Analyze configuration for issues
istioctl analyze -n bank-of-westeros

# Describe pod with Istio perspective
istioctl x describe pod -l app=userservice -n bank-of-westeros

# Check mTLS mode on proxy
POD=$(kubectl get pod -l app=userservice -n bank-of-westeros -o jsonpath='{.items[0].metadata.name}')
istioctl proxy-config cluster -n bank-of-westeros $POD
```

**7. Frontend Impact**
```bash
# Access frontend (replace with your setup)
kubectl port-forward -n bank-of-westeros svc/frontend 8080:80

# Try to login - should see:
# - "503 Service Unavailable"
# - "Connection failed" errors
# - Timeout messages
```

## Investigation Path (Realistic Troubleshooting Flow)

### Step 1: Incident Report
**User Report**: "Login is broken, getting 503 errors"

### Step 2: Check Service Health
```bash
kubectl get pods -n bank-of-westeros
# Notice: userservice is Running but 0/2 (NotReady)
```

### Step 3: Check Logs
```bash
kubectl logs deployment/userservice -n bank-of-westeros -c userservice --tail=50
# See: Connection errors, database timeouts
```

### Step 4: Check Readiness Probe
```bash
kubectl describe pod -l app=userservice -n bank-of-westeros
# Events: "Readiness probe failed: dial tcp: connection refused"
```

### Step 5: Investigate Service Mesh (if Istio is known)
```bash
kubectl get peerauthentication,destinationrule -n bank-of-westeros
# Discover: STRICT mTLS policy exists
```

### Step 6: Analyze Istio Proxy Logs
```bash
kubectl logs deployment/userservice -n bank-of-westeros -c istio-proxy --tail=50
# See: "TLS handshake timeout", "upstream connect error"
```

### Step 7: Identify Root Cause
```bash
# Check PeerAuthentication
kubectl get peerauthentication userservice-strict-mtls -n bank-of-westeros -o yaml
# Shows: mtls.mode: STRICT

# Check DestinationRule
kubectl get destinationrule accounts-db-mtls -n bank-of-westeros -o yaml
# Shows: trafficPolicy.tls.mode: DISABLE

# ROOT CAUSE: Mismatch! STRICT mTLS required but TLS disabled on destination
```

### Step 8: Resolution
```bash
./scenarios/mtls-mismatch-scenario.sh revert
```

## Expected Behavior

### Before Scenario Injection
- userservice: **Running and Ready (2/2)**
- mTLS: Default mode (likely PERMISSIVE or none)
- Service-to-service communication: Working normally
- Frontend: User login and operations working

### After Scenario Injection
- PeerAuthentication policy created: **STRICT mTLS on userservice**
- DestinationRule created: **TLS DISABLED for accounts-db**
- userservice: **Running but NotReady (0/2)**
- Readiness probe: **Failing** (cannot connect without mTLS)
- Application logs: **Connection/TLS errors**
- Istio proxy logs: **Handshake failures**
- Frontend: **503 errors** on user operations

### After Revert
- Policies removed
- userservice restarted
- userservice: **Running and Ready (2/2)**
- All services: **Normal operation restored**

## Revert Failure
```bash
# Specific namespace
NAMESPACE=bank-of-westeros ./scenarios/mtls-mismatch-scenario.sh revert

# Or using batch cleanup
./batch/restore-all-scenarios.sh
```

## Key Learning Points

### 1. mTLS Policy Consistency
- **PeerAuthentication** controls inbound mTLS requirements
- **DestinationRule** controls outbound TLS behavior
- **Both must align** for successful communication

### 2. Service Mesh Gradual Adoption
- Don't enable STRICT mTLS on individual services in isolation
- Use namespace-level or mesh-wide policies for consistency
- Test with PERMISSIVE mode before moving to STRICT

### 3. Health Check Considerations
- Readiness/liveness probes must support mTLS if STRICT is enforced
- Consider using `rewrite` or `PERMISSIVE` mode for probes
- Or exclude probe ports from STRICT mTLS using port-level configuration

### 4. Investigation Tools
- Application logs (connection errors)
- Istio proxy logs (TLS handshake details)
- `istioctl analyze` (configuration validation)
- `istioctl x describe` (policy visualization)
- Pod events (probe failures)

## Common Variations in Production

### Variation 1: Missing mTLS Certificates
- Root cause: Certificate provisioning failure
- Symptom: Similar handshake errors but different root cause
- Resolution: Check cert-manager, Istio CA, SDS

### Variation 2: Port-Level mTLS Mismatch
- Root cause: Different mTLS modes for different ports
- Symptom: Some endpoints work, others fail
- Resolution: Review port-level `portLevelMtls` configuration

### Variation 3: Cross-Namespace Communication
- Root cause: mTLS policy applies to workload namespace only
- Symptom: External services cannot connect
- Resolution: Use `PERMISSIVE` or configure proper mesh-wide policies

### Variation 4: Legacy Non-Mesh Services
- Root cause: Non-Istio service trying to connect to STRICT mTLS service
- Symptom: Connection refused (no sidecar for mTLS)
- Resolution: Inject sidecar or use `PERMISSIVE` mode

## Files Created/Modified

### Created Resources
- `PeerAuthentication: userservice-strict-mtls` (STRICT mode)
- `DestinationRule: accounts-db-mtls` (TLS DISABLE)

### No Deployment Changes
- No deployment manifests modified
- Only Istio policy resources created
- Changes take effect via Istio control plane propagation

## Cleanup
The scenario automatically cleans up all created resources during revert:
- Removes PeerAuthentication policy
- Removes DestinationRule
- Restarts userservice to clear cached configurations
- No manual cleanup required

## Troubleshooting the Scenario Itself

### Scenario has limited effect (pods remain healthy)
**Possible causes:**
1. Istio not installed → Check `kubectl get ns istio-system`
2. Sidecar not injected → Check pod container count
3. Namespace not labeled → Check `istio-injection=enabled` label
4. Default mesh policy overrides workload policy

### Pods immediately crash
**Possible causes:**
1. Application already has mTLS issues
2. Incompatible Istio version
3. Check baseline health before scenario injection

### Revert doesn't restore service
**Resolution:**
```bash
# Manual cleanup
kubectl delete peerauthentication userservice-strict-mtls -n bank-of-westeros
kubectl delete destinationrule accounts-db-mtls -n bank-of-westeros
kubectl rollout restart deployment/userservice -n bank-of-westeros

# Wait for rollout
kubectl rollout status deployment/userservice -n bank-of-westeros
```

## Related Scenarios
- **network-policy-scenario**: Similar symptoms (connection failures) but different layer (L3/L4 vs L7)
- **config-misconfigured-scenario**: Also causes connection failures but at application config level

## Additional Resources
- [Istio mTLS Documentation](https://istio.io/latest/docs/tasks/security/authentication/mtls-migration/)
- [PeerAuthentication Reference](https://istio.io/latest/docs/reference/config/security/peer_authentication/)
- [DestinationRule Reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/)
- [Istio Security Best Practices](https://istio.io/latest/docs/ops/best-practices/security/)

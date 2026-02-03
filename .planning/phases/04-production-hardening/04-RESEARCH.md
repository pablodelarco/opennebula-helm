# Phase 4: Production Hardening - Research

**Researched:** 2026-02-03
**Domain:** Kubernetes networking, OpenNebula monitoring/transfer subsystems, pod identity
**Confidence:** HIGH

## Summary

This research addresses four production deployment issues discovered during real-world usage of the OpenNebula Helm chart:

1. **Port 4124 UDP/TCP missing** - Hypervisor monitoring agents cannot push metrics to onemonitord
2. **Port 22 SSH missing** - SSH transfer manager cannot connect to hypervisors for image operations
3. **VNM transparent proxy needs configuration** - OneGate/service access from VMs requires MONITOR_ADDRESS and HOSTNAME settings
4. **Hostname instability** - Pod hostname changes on reschedule, breaking hypervisor SSH configuration

The primary issues stem from incomplete port exposure in the Dockerfile/Service/StatefulSet and missing configuration for how oned identifies itself to hypervisors. OpenNebula's monitoring and transfer subsystems require bidirectional network connectivity: oned initiates SSH connections to hypervisors, while hypervisor probe agents push monitoring data back to the frontend.

**Primary recommendation:** Add port 4124 (TCP+UDP) and port 22 (TCP) to Dockerfile EXPOSE and Kubernetes Service/StatefulSet definitions. Configure HOSTNAME and MONITOR_ADDRESS via values.yaml to provide stable, predictable addresses for hypervisor communication. Use StatefulSet's inherent stable hostname pattern for pod identity.

## Standard Stack

### Core Configuration

| Component | Parameter | Purpose | Default |
|-----------|-----------|---------|---------|
| oned.conf | HOSTNAME | Frontend address for driver operations | auto-detect |
| monitord.conf | MONITOR_ADDRESS | Where probes send monitoring data | auto |
| monitord.conf | ADDRESS | Network binding for listener | 0.0.0.0 |
| monitord.conf | PORT | Monitoring port | 4124 |
| Kubernetes | StatefulSet serviceName | DNS pattern for stable hostname | headless-svc |

### Ports Required for Production

| Port | Protocol | Direction | Service | Why Needed |
|------|----------|-----------|---------|------------|
| 2633 | TCP | In | oned API | Already exposed |
| 4124 | TCP+UDP | In | onemonitord | Hypervisor probes push metrics |
| 22 | TCP | Out + In | SSH | Transfer manager, driver operations |
| 2616 | TCP | In | FireEdge | Already exposed |
| 2474 | TCP | In | OneFlow | Already exposed |
| 5030 | TCP | In | OneGate | Already exposed |

**Critical:** Port 4124 requires BOTH TCP and UDP. Monitoring messages use UDP for efficiency but may fall back to TCP.

### Kubernetes Service Types for UDP

| Service Type | UDP Support | Use Case |
|--------------|-------------|----------|
| ClusterIP | Yes | Internal cluster access |
| NodePort | Yes | External access via node IP:port |
| LoadBalancer | Yes (cloud-dependent) | External access via LB |
| Headless | Yes | Direct pod DNS |

## Architecture Patterns

### Pattern 1: Multi-Protocol Service Definition

**What:** Kubernetes Services support mixed TCP/UDP ports in the same definition
**When to use:** When a service needs both protocols (like monitord)
**Example:**
```yaml
# Source: Kubernetes Service documentation
apiVersion: v1
kind: Service
metadata:
  name: {{ include "opennebula.fullname" . }}
spec:
  selector:
    {{- include "opennebula.selectorLabels" . | nindent 4 }}
  ports:
    - port: 4124
      targetPort: 4124
      protocol: TCP
      name: monitord-tcp
    - port: 4124
      targetPort: 4124
      protocol: UDP
      name: monitord-udp
    - port: 22
      targetPort: 22
      protocol: TCP
      name: ssh
```

### Pattern 2: StatefulSet Stable Hostname

**What:** StatefulSet provides predictable hostname pattern `{statefulset-name}-{ordinal}`
**When to use:** When external systems need consistent hostname for configuration
**Example:**
```yaml
# Source: Kubernetes StatefulSet documentation
# Given StatefulSet "opennebula" and headless service "opennebula-headless"
# Pod gets hostname: opennebula-0
# FQDN: opennebula-0.opennebula-headless.{namespace}.svc.cluster.local
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ include "opennebula.fullname" . }}
spec:
  serviceName: {{ include "opennebula.fullname" . }}-headless
  # Pod hostname = opennebula-0 (stable across rescheduling)
```

**Key insight:** StatefulSets already provide stable hostnames. The issue is that OpenNebula's HOSTNAME config defaults to "auto-detect" which may resolve to the internal pod IP instead of the predictable DNS name.

### Pattern 3: ConfigMap for monitord.conf

**What:** Mount monitord.conf as ConfigMap to set MONITOR_ADDRESS
**When to use:** When MONITOR_ADDRESS needs to be configurable via Helm values
**Example:**
```yaml
# Source: Helm patterns + OpenNebula docs
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "opennebula.fullname" . }}-config
data:
  monitord.conf: |
    NETWORK = [
      ADDRESS = "0.0.0.0",
      {{- if .Values.opennebula.monitorAddress }}
      MONITOR_ADDRESS = "{{ .Values.opennebula.monitorAddress }}",
      {{- else }}
      MONITOR_ADDRESS = "auto",
      {{- end }}
      PORT = 4124,
      THREADS = 8,
      PUBKEY = "",
      PRIKEY = ""
    ]
```

### Pattern 4: Explicit HOSTNAME in oned.conf

**What:** Set HOSTNAME to the StatefulSet's FQDN for driver operations
**When to use:** When auto-detection returns internal IP instead of resolvable hostname
**Example:**
```yaml
# In entrypoint.sh or ConfigMap
# Set HOSTNAME to the predictable StatefulSet FQDN
HOSTNAME = "{{ include "opennebula.fullname" . }}-0.{{ include "opennebula.fullname" . }}-headless.{{ .Release.Namespace }}.svc.cluster.local"
```

### Anti-Patterns to Avoid

- **Using auto-detect for HOSTNAME in containers:** Auto-detection may return pod IP, which changes on reschedule
- **Exposing only TCP for port 4124:** UDP is required for efficient monitoring probe communication
- **Assuming SSH works without explicit port exposure:** SSH port 22 must be in both containerPort and Service
- **Using NodePort for internal-only traffic:** If hypervisors are in-cluster, ClusterIP suffices; use NodePort/LoadBalancer only for external hypervisors

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Stable pod hostname | Custom sidecar to set hostname | StatefulSet + headless service | Built-in K8s feature |
| Mixed TCP/UDP service | Two separate Services | Single Service with multiple port entries | K8s supports mixed protocols |
| Hostname discovery | Custom init container to write hostname | Environment variable from downward API | Simpler, built-in |
| MONITOR_ADDRESS auto | Let OpenNebula auto-detect | Explicit configuration via ConfigMap | Auto fails in containers |

**Key insight:** Most production issues are configuration problems, not missing features. Kubernetes and OpenNebula both have the capabilities; they just need to be configured correctly.

## Common Pitfalls

### Pitfall 1: MONITOR_ADDRESS "auto" Fails in Containers

**What goes wrong:** Monitoring probes on hypervisors cannot reach the frontend; hosts show as ERROR
**Why it happens:** MONITOR_ADDRESS="auto" uses SSH connection source to determine address. In containers, this may resolve to an internal pod IP that's not routable from hypervisors.
**How to avoid:**
- Set explicit MONITOR_ADDRESS in monitord.conf
- Use the Service ClusterIP, NodePort IP, or LoadBalancer IP depending on where hypervisors are
- For external hypervisors, use LoadBalancer or NodePort IP
**Warning signs:**
- `onehost list` shows hosts in ERROR state
- monitord.log shows "no messages received"
- Hypervisor /var/log/one shows connection timeouts to wrong IP

### Pitfall 2: Missing UDP Port for Monitoring

**What goes wrong:** Monitoring messages don't arrive even with correct MONITOR_ADDRESS
**Why it happens:** Kubernetes Service only exposes TCP by default; UDP must be explicitly specified
**How to avoid:** Add explicit `protocol: UDP` port entry in Service definition
**Warning signs:**
- Same symptoms as Pitfall 1
- TCP connection to 4124 works but monitoring still fails
- tcpdump on pod shows UDP packets being dropped

### Pitfall 3: SSH Transfer Operations Fail

**What goes wrong:** VM deployment fails; image transfer times out; TM_MAD errors in logs
**Why it happens:** SSH port 22 not exposed; hypervisors cannot SSH back to frontend for some operations
**How to avoid:**
- Expose port 22 in Dockerfile, containerPort, and Service
- Verify SSH bidirectional connectivity (frontend->hypervisor AND hypervisor->frontend)
- For some TM modes (ssh), frontend's SSH must be reachable from hypervisors
**Warning signs:**
- TM_MAD errors in oned.log
- "Connection refused" to frontend port 22 from hypervisor
- Image clone operations hang or fail

### Pitfall 4: HOSTNAME Auto-Detection Returns Pod IP

**What goes wrong:** Driver operations fail; hypervisors try to connect to wrong address
**Why it happens:** HOSTNAME defaults to auto-detect, which in containers often returns the pod IP (10.x.x.x) instead of a resolvable hostname
**How to avoid:**
- Explicitly set HOSTNAME in oned.conf to the StatefulSet FQDN
- Alternatively, use the Service ClusterIP/NodePort IP
**Warning signs:**
- Driver log shows connections to unexpected IP addresses
- Hypervisors cannot resolve hostname during VM operations

### Pitfall 5: VNM Transparent Proxy Misconfigured

**What goes wrong:** VMs cannot reach OneGate; contextualization fails
**Why it happens:** Transparent proxy requires correct `:remote_addr` in OpenNebulaNetwork.conf pointing to reachable frontend address
**How to avoid:**
- Configure VNM transparent proxy with Service LoadBalancer IP or accessible NodePort
- Ensure Security Groups allow traffic to proxy ports
- Sync configuration with `onehost sync -f`
**Warning signs:**
- VMs hang during contextualization
- OneGate API unreachable from inside VMs
- Context TOKEN not available

## Code Examples

### Dockerfile EXPOSE Addition

```dockerfile
# Source: Current Dockerfile + production requirements
# Expose ports
# 2633 - oned XML-RPC API
# 2616 - FireEdge/Sunstone web UI
# 2474 - OneFlow API
# 5030 - OneGate API
# 4124 - Monitord (TCP+UDP for hypervisor probes)
# 22   - SSH (transfer manager, driver operations)
EXPOSE 2633 2616 2474 5030 4124 22
```

### Service with UDP Port

```yaml
# Source: Kubernetes multi-protocol Service pattern
apiVersion: v1
kind: Service
metadata:
  name: {{ include "opennebula.fullname" . }}
spec:
  type: {{ .Values.service.type }}
  selector:
    {{- include "opennebula.selectorLabels" . | nindent 4 }}
  ports:
    - port: 2633
      targetPort: 2633
      protocol: TCP
      name: oned
    - port: 2616
      targetPort: {{ if .Values.fireedgeProxy.enabled }}8080{{ else }}2616{{ end }}
      protocol: TCP
      name: fireedge
    - port: 2474
      targetPort: 2474
      protocol: TCP
      name: oneflow
    - port: 5030
      targetPort: 5030
      protocol: TCP
      name: onegate
    # NEW: Monitoring port (TCP)
    - port: 4124
      targetPort: 4124
      protocol: TCP
      name: monitord-tcp
    # NEW: Monitoring port (UDP - required for probe messages)
    - port: 4124
      targetPort: 4124
      protocol: UDP
      name: monitord-udp
    # NEW: SSH for transfer manager
    - port: 22
      targetPort: 22
      protocol: TCP
      name: ssh
```

### StatefulSet containerPorts Addition

```yaml
# Source: Current StatefulSet + production requirements
containers:
  - name: opennebula
    ports:
      # Existing ports...
      - name: oned
        containerPort: 2633
        protocol: TCP
      # ... other existing ports ...

      # NEW: Monitoring port (TCP + UDP)
      - name: monitord-tcp
        containerPort: 4124
        protocol: TCP
      - name: monitord-udp
        containerPort: 4124
        protocol: UDP
      # NEW: SSH
      - name: ssh
        containerPort: 22
        protocol: TCP
```

### Values.yaml Additions for Hostname/Monitor Configuration

```yaml
# Source: Helm patterns + OpenNebula docs
opennebula:
  ## Admin password for oneadmin user
  adminPassword: "opennebula"

  ## HOSTNAME for oned.conf - how oned identifies itself to hypervisors
  ## Options:
  ##   - "auto" - auto-detect (may fail in containers)
  ##   - "" (empty) - use StatefulSet FQDN (recommended)
  ##   - explicit hostname/IP - use specific value
  ## Default: uses StatefulSet FQDN for stable identity
  hostname: ""

  ## MONITOR_ADDRESS for monitord.conf - where probes send data
  ## Options:
  ##   - "auto" - auto-detect from SSH (may fail in containers)
  ##   - explicit IP/hostname - use specific value
  ## For external hypervisors, set to LoadBalancer IP or NodePort-accessible IP
  ## Default: auto (works if hypervisors can route to pod network)
  monitorAddress: "auto"

## VNM Transparent Proxy configuration
## Required for VMs to access OneGate when using isolated virtual networks
vnm:
  tproxy:
    enabled: false
    ## Remote address for OneGate proxy (frontend address reachable from hypervisors)
    ## If empty, uses Service address
    onegateRemoteAddr: ""
    ## Debug level (0=ERROR, 1=WARNING, 2=INFO, 3=DEBUG)
    debugLevel: 0
```

### Entrypoint.sh HOSTNAME Configuration

```bash
# Source: OpenNebula docs + Kubernetes patterns
# ----------------------------------------------------------------------------
# HOSTNAME Configuration for Driver Operations
# ----------------------------------------------------------------------------
OPENNEBULA_HOSTNAME="${OPENNEBULA_HOSTNAME:-}"

if [ -n "$OPENNEBULA_HOSTNAME" ] && [ "$OPENNEBULA_HOSTNAME" != "auto" ]; then
    echo "Setting explicit HOSTNAME in oned.conf: $OPENNEBULA_HOSTNAME"
    # Uncomment and set HOSTNAME
    sed -i 's/^#\s*HOSTNAME\s*=.*/HOSTNAME = "'"${OPENNEBULA_HOSTNAME}"'"/' /etc/one/oned.conf
    # If not found as comment, add it
    grep -q "^HOSTNAME" /etc/one/oned.conf || \
        echo "HOSTNAME = \"${OPENNEBULA_HOSTNAME}\"" >> /etc/one/oned.conf
fi
```

### ConfigMap for monitord.conf (Optional)

```yaml
# Source: OpenNebula monitord.conf structure
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "opennebula.fullname" . }}-monitord
data:
  monitord.conf: |
    # OpenNebula Monitoring Configuration
    # Generated by Helm chart

    NETWORK = [
      ADDRESS = "0.0.0.0",
      {{- if and .Values.opennebula.monitorAddress (ne .Values.opennebula.monitorAddress "auto") }}
      MONITOR_ADDRESS = "{{ .Values.opennebula.monitorAddress }}",
      {{- else }}
      MONITOR_ADDRESS = "auto",
      {{- end }}
      PORT = 4124,
      THREADS = 8,
      PUBKEY = "",
      PRIKEY = ""
    ]

    # ... rest of monitord.conf default content
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single Service for all protocols | Mixed TCP/UDP in single Service | K8s 1.20+ | Simpler configuration |
| Manual hostname file editing | Downward API for pod metadata | K8s stable | Automated discovery |
| MONITOR_ADDRESS=auto | Explicit address configuration | OpenNebula 6.0+ | Required for containers |
| Sunstone VNC proxy | FireEdge with Guacamole | OpenNebula 6.0+ | Better WebSocket support |

**Current best practice:**
- Explicit HOSTNAME and MONITOR_ADDRESS for containerized deployments
- StatefulSet for stable network identity
- Mixed TCP/UDP Service for monitoring
- SSH exposed only if using ssh transfer mode or remote hypervisors need to connect back

## Open Questions

1. **External vs Internal Hypervisors**
   - What we know: Port exposure strategy differs based on hypervisor location
   - What's unclear: User's deployment topology
   - Recommendation: Document both scenarios; default to ClusterIP with NodePort/LoadBalancer as optional

2. **SSH Server in Container**
   - What we know: Port 22 exposure is needed; whether SSH server runs in container varies
   - What's unclear: If current image includes sshd or if it's only for outbound SSH
   - Recommendation: Check if sshd is installed and configured in current image; document use case

3. **VNM Transparent Proxy Scope**
   - What we know: Configuration lives in hypervisor-side files
   - What's unclear: How Helm chart can influence hypervisor configuration
   - Recommendation: Document as post-install configuration; provide config templates

## Sources

### Primary (HIGH confidence)
- [OpenNebula 6.10 Monitoring Configuration](https://docs.opennebula.io/6.10/installation_and_configuration/opennebula_services/monitoring.html) - Port 4124, MONITOR_ADDRESS
- [OpenNebula 7.0 oned Configuration](https://docs.opennebula.io/7.0/product/operation_references/opennebula_services_configuration/oned/) - HOSTNAME parameter
- [Kubernetes Service Documentation](https://kubernetes.io/docs/concepts/services-networking/service/) - Multi-protocol services
- [Kubernetes StatefulSet Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) - Stable network identity
- [Kubernetes DNS for Pods and Services](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/) - Hostname/subdomain configuration

### Secondary (MEDIUM confidence)
- [OpenNebula Transparent Proxies](https://docs.opennebula.io/6.10/management_and_operations/network_management/tproxy.html) - VNM tproxy configuration
- [kvaps/kube-opennebula](https://github.com/kvaps/kube-opennebula) - Reference implementation patterns
- [OpenNebula GitHub oned.conf](https://github.com/OpenNebula/one/blob/master/share/etc/oned.conf) - Default configuration

### Tertiary (LOW confidence)
- Forum discussions on SSH port configuration for containerized deployments

## Metadata

**Confidence breakdown:**
- Port configuration: HIGH - Kubernetes Service/pod documentation is authoritative
- HOSTNAME/MONITOR_ADDRESS: HIGH - OpenNebula official docs explicit
- VNM transparent proxy: MEDIUM - Configuration is hypervisor-side, chart can only document
- SSH requirements: MEDIUM - Depends on TM_MAD mode and deployment topology

**Research date:** 2026-02-03
**Valid until:** 2026-03-03 (30 days - stable technologies)

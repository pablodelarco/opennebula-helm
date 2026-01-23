# Architecture Research: OpenNebula

**Domain:** Cloud Management Platform (Private Cloud Infrastructure)
**Researched:** 2026-01-23
**Confidence:** HIGH (verified with official documentation)

## System Overview

```
                                   KUBERNETES CLUSTER
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           OPENNEBULA CONTROL PLANE                                   │
│                                                                                      │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌────────────────┐  │
│  │    FireEdge     │  │    Sunstone     │  │    OneFlow      │  │    OneGate     │  │
│  │   (GUI + VNC)   │  │  (Legacy GUI)   │  │  (Orchestrator) │  │  (VM Comms)    │  │
│  │    :2616        │  │     :9869       │  │     :2474       │  │     :5030      │  │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘  └───────┬────────┘  │
│           │                    │                    │                   │           │
│           └────────────────────┴────────────────────┴───────────────────┘           │
│                                         │                                            │
│                                         ▼                                            │
│                         ┌───────────────────────────────┐                            │
│                         │         ONED (Core)           │                            │
│                         │        XML-RPC API            │                            │
│                         │           :2633               │                            │
│                         └───────────────┬───────────────┘                            │
│                                         │                                            │
│           ┌─────────────────────────────┼─────────────────────────────┐              │
│           │                             │                             │              │
│           ▼                             ▼                             ▼              │
│  ┌─────────────────┐       ┌─────────────────┐           ┌─────────────────┐        │
│  │    Scheduler    │       │   onemonitord   │           │    SSH Agent    │        │
│  │   (mm_sched)    │       │   (Monitoring)  │           │  (Key Mgmt)     │        │
│  │  auto-started   │       │      :4124      │           │                 │        │
│  └─────────────────┘       └─────────────────┘           └────────┬────────┘        │
│                                                                   │                 │
├───────────────────────────────────────────────────────────────────┼─────────────────┤
│                           DATA LAYER                              │                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐    │                 │
│  │    MariaDB      │  │   Datastores    │  │     etcd        │    │                 │
│  │   (State DB)    │  │  (VM Images)    │  │ (HA Consensus)  │    │                 │
│  │     :3306       │  │   (PV/NFS)      │  │  (optional)     │    │                 │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘    │                 │
└───────────────────────────────────────────────────────────────────┼─────────────────┘
                                                                    │
                                                     SSH :22        │
                                                                    ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           HYPERVISOR NODES (External)                                │
│                                                                                      │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐                      │
│  │   KVM Node 1    │  │   KVM Node 2    │  │   LXC Node 1    │     ...              │
│  │   libvirtd      │  │   libvirtd      │  │   lxc-tools     │                      │
│  │   oneadmin SSH  │  │   oneadmin SSH  │  │   oneadmin SSH  │                      │
│  │   Probes Agent  │  │   Probes Agent  │  │   Probes Agent  │                      │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | Port | Container? | Dependency |
|-----------|----------------|------|------------|------------|
| **oned** | Core daemon - VM, network, storage, user management; XML-RPC API | 2633 | YES | MariaDB |
| **mm_sched** | Scheduler - assigns pending VMs to hosts | N/A | YES (with oned) | oned |
| **onemonitord** | Monitoring - collects host/VM metrics via probes | 4124 TCP/UDP | YES (with oned) | oned |
| **FireEdge** | Next-gen web UI + Guacamole for VNC/SSH | 2616 | YES | oned |
| **Sunstone** | Legacy web UI (being replaced by FireEdge) | 9869 | YES | oned |
| **OneFlow** | Multi-VM service orchestration and auto-scaling | 2474 | YES | oned |
| **OneGate** | VM-to-OpenNebula communication gateway | 5030 | YES | oned |
| **SSH Agent** | Key management for hypervisor connections | N/A | YES (with oned) | oned |
| **MariaDB** | Persistent state storage | 3306 | YES (subchart) | None |

## Data Flow

### 1. User Request Flow (Create VM)

```
User (Browser/CLI)
        │
        ▼
┌───────────────────┐
│  FireEdge/CLI     │ ─────▶ Authenticate via oned
│                   │
└────────┬──────────┘
         │ XML-RPC
         ▼
┌───────────────────┐
│      oned         │ ─────▶ Validate user/quota/ACL
│                   │ ─────▶ Create VM record in DB
│                   │ ─────▶ Queue VM as "pending"
└────────┬──────────┘
         │
         ▼
┌───────────────────┐
│    mm_sched       │ ─────▶ Evaluate host capacity
│   (Scheduler)     │ ─────▶ Apply placement policies
│                   │ ─────▶ Select target host
└────────┬──────────┘
         │ XML-RPC
         ▼
┌───────────────────┐
│      oned         │ ─────▶ Execute VMM driver (one_vmm_exec)
│                   │
└────────┬──────────┘
         │ SSH
         ▼
┌───────────────────┐
│  Hypervisor Node  │ ─────▶ libvirtd creates VM
│                   │ ─────▶ VM boots
└───────────────────┘
```

### 2. Monitoring Flow (Push Model)

```
┌───────────────────┐
│  Hypervisor Node  │
│   Probe Agent     │ ─────▶ Collect host/VM metrics
│                   │        (CPU, memory, disk, network)
└────────┬──────────┘
         │ UDP/TCP :4124
         ▼
┌───────────────────┐
│   onemonitord     │ ─────▶ Process metrics
│   (Frontend)      │ ─────▶ Detect state changes
└────────┬──────────┘
         │
         ▼
┌───────────────────┐
│      oned         │ ─────▶ Update DB state
│                   │ ─────▶ Trigger hooks if needed
└────────┬──────────┘
         │
         ▼
┌───────────────────┐
│     MariaDB       │ ─────▶ Persist time-series data
└───────────────────┘
```

### 3. OneFlow Service Orchestration

```
┌───────────────────┐
│     OneFlow       │ ─────▶ Parse service template
│                   │        (roles, dependencies)
└────────┬──────────┘
         │ XML-RPC
         ▼
┌───────────────────┐
│      oned         │ ─────▶ Create VMs in dependency order
│                   │        (wait for "ready" state)
└────────┬──────────┘
         │
         ▼
┌───────────────────┐
│   OneGate         │ ◀────── VMs report ready via API
│                   │ ◀────── VMs exchange information
│                   │ ─────▶ Trigger scale events
└───────────────────┘
```

## Recommended Helm Chart Structure

```
opennebula/
├── Chart.yaml
├── values.yaml
├── charts/
│   └── mariadb/              # Bitnami subchart dependency
├── templates/
│   ├── _helpers.tpl
│   │
│   ├── # Core Services (Phase 1)
│   ├── oned/
│   │   ├── statefulset.yaml  # oned + scheduler + ssh-agent + monitord
│   │   ├── service.yaml      # ClusterIP for :2633, :4124
│   │   ├── configmap.yaml    # oned.conf, sched.conf, monitord.conf
│   │   └── secret.yaml       # oneadmin credentials, SSH keys
│   │
│   ├── # Web UI (Phase 2)
│   ├── fireedge/
│   │   ├── deployment.yaml
│   │   ├── service.yaml      # :2616
│   │   └── configmap.yaml
│   │
│   ├── # Optional Services (Phase 3)
│   ├── oneflow/
│   │   ├── deployment.yaml
│   │   ├── service.yaml      # :2474
│   │   └── configmap.yaml
│   │
│   ├── onegate/
│   │   ├── deployment.yaml
│   │   ├── service.yaml      # :5030
│   │   └── configmap.yaml
│   │
│   ├── # Storage (Phase 1)
│   ├── pvc-datastores.yaml   # RWX for /var/lib/one/datastores
│   ├── pvc-var.yaml          # RWO for /var/lib/one
│   │
│   └── # Networking (Phase 2)
│   └── ingress.yaml          # Optional ingress for FireEdge
```

### Structure Rationale

- **oned as StatefulSet:** Requires stable network identity for SSH key distribution and HA leader election
- **Scheduler/Monitord with oned:** Auto-started by oned, tight coupling makes separate containers unnecessary
- **FireEdge separate:** Stateless, can scale horizontally, different lifecycle
- **OneFlow/OneGate optional:** Not required for basic operation, can enable via values.yaml

## Architectural Patterns

### Pattern 1: Sidecar SSH Agent

**What:** Run SSH agent as init container or sidecar to manage keys
**When to use:** When oned needs to connect to external hypervisors
**Trade-offs:** Adds complexity but essential for hypervisor management

**Example:**
```yaml
initContainers:
  - name: ssh-keygen
    image: alpine
    command: ["sh", "-c"]
    args:
      - |
        if [ ! -f /var/lib/one/.ssh/id_rsa ]; then
          ssh-keygen -t rsa -f /var/lib/one/.ssh/id_rsa -N ""
        fi
    volumeMounts:
      - name: ssh-keys
        mountPath: /var/lib/one/.ssh
```

### Pattern 2: Leader Election for HA (Advanced)

**What:** Use Raft consensus for multi-oned deployments
**When to use:** Production deployments requiring high availability
**Trade-offs:** Requires 3 or 5 replicas, shared filesystem, floating IP

**Note:** This is complex for initial Helm chart. Recommend single-replica for v1.

### Pattern 3: External Hypervisor Communication

**What:** oned connects to external KVM/LXC hosts via SSH
**When to use:** Always - hypervisors cannot run inside Kubernetes
**Trade-offs:** Requires:
  - SSH key distribution to hypervisor nodes
  - Network connectivity from K8s pods to hypervisor SSH
  - `oneadmin` user on hypervisors with passwordless sudo

## Container vs Host Considerations

### Must Run in Containers (Control Plane)

| Component | Container Requirements |
|-----------|------------------------|
| oned | Standard container, needs DB access, SSH outbound |
| scheduler | Runs with oned (same process space) |
| onemonitord | Runs with oned, needs port 4124 exposed |
| FireEdge | Standard container, WebSocket support |
| OneFlow | Standard container |
| OneGate | Standard container, must be reachable from VMs |

### Cannot Run in Containers (Hypervisor Nodes)

| Component | Why Host-Only |
|-----------|---------------|
| libvirtd | Requires host kernel access, hardware virtualization |
| qemu-kvm | Requires /dev/kvm, host networking |
| LXC | Requires cgroups, namespaces on host |
| Probe agents | Need access to host metrics, libvirt socket |

### Networking Implications

```
Kubernetes Pods                    External Hypervisors
┌────────────────┐                 ┌────────────────┐
│     oned       │────SSH:22──────▶│   KVM Host     │
│   (outbound)   │                 │  libvirtd:16509│
└────────────────┘                 └────────────────┘
        ▲
        │ TCP/UDP:4124 (inbound)
        │
┌────────────────┐
│  Probe Agent   │ (push monitoring data to oned)
│  on KVM Host   │
└────────────────┘
```

**Key Insight:** The control plane runs in K8s, but it manages EXTERNAL hypervisor hosts via SSH. This is not a traditional microservices pattern - it's a management plane orchestrating bare-metal/VM infrastructure.

## Suggested Build Order

Based on component dependencies:

### Phase 1: Foundation (MVP)
1. **MariaDB** - No dependencies, foundation for everything
2. **oned StatefulSet** - Depends on MariaDB, core of system
3. **Basic ConfigMaps/Secrets** - oned.conf, credentials
4. **SSH key generation** - Required for hypervisor communication

**Deliverable:** Working oned that can accept CLI commands

### Phase 2: Web Interface
5. **FireEdge Deployment** - Depends on oned API
6. **Ingress for FireEdge** - External access

**Deliverable:** Functional web UI for managing OpenNebula

### Phase 3: Advanced Features
7. **OneFlow** - For multi-VM service orchestration
8. **OneGate** - For VM self-service and elasticity
9. **HA configuration** - Multiple oned replicas with Raft

**Deliverable:** Full-featured deployment

### Phase 4: Productionization
10. **Monitoring integration** (Prometheus metrics)
11. **Backup/restore procedures**
12. **Documentation and examples**

## Anti-Patterns

### Anti-Pattern 1: Hypervisors in Kubernetes

**What people do:** Try to run libvirtd/KVM inside Kubernetes pods
**Why it's wrong:** Requires privileged mode, host network, /dev access; defeats container isolation; fragile
**Do this instead:** Keep hypervisors external, manage them via SSH from containerized oned

### Anti-Pattern 2: Shared SQLite Database

**What people do:** Use SQLite (default) for multi-replica deployments
**Why it's wrong:** SQLite doesn't support concurrent writes; will corrupt data
**Do this instead:** Always use MariaDB/MySQL for any serious deployment

### Anti-Pattern 3: Baking Secrets into Images

**What people do:** Include oneadmin password or SSH keys in Docker image
**Why it's wrong:** Security risk; prevents image reuse
**Do this instead:** Use Kubernetes Secrets mounted as volumes or environment variables

### Anti-Pattern 4: Single Container for All Services

**What people do:** Run all OpenNebula services in one container
**Why it's wrong:** Harder to debug, scale, update independently
**Do this instead:** Separate FireEdge/OneFlow/OneGate into own deployments; keep oned+scheduler together (they're tightly coupled)

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Hypervisor nodes | SSH + oneadmin user | Keys must be pre-distributed |
| Storage backends | NFS/Ceph via datastores | Requires PV provisioner |
| LDAP/AD | AUTH_MAD driver | Optional, configured in oned.conf |
| Prometheus | Metrics exporter | Community exporter available |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| oned <-> MariaDB | TCP :3306 | Standard MySQL protocol |
| oned <-> scheduler | Internal (same process) | Auto-started, shares memory |
| oned <-> FireEdge | XML-RPC :2633 | HTTP-based |
| oned <-> OneFlow | XML-RPC :2633 | HTTP-based |
| oned <-> OneGate | XML-RPC :2633 | HTTP-based |
| oned <-> Hypervisors | SSH :22 | Requires key auth |
| Monitord <-> Probes | TCP/UDP :4124 | Custom protocol (push) |

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 1-10 hosts | Single oned replica, single MariaDB |
| 10-100 hosts | Consider MariaDB replication, tune monitoring intervals |
| 100+ hosts | HA oned (3 replicas), dedicated monitoring DB, probe tuning |

### Scaling Priorities

1. **First bottleneck:** MariaDB - high write load from monitoring data
   - **Fix:** MariaDB replication, SSD storage, connection pooling

2. **Second bottleneck:** Scheduler decision time
   - **Fix:** Tune SCHED_INTERVAL, adjust scheduling algorithms

3. **Third bottleneck:** SSH connections to hypervisors
   - **Fix:** SSH connection multiplexing (already default in OpenNebula config)

## Sources

### Official Documentation (HIGH confidence)
- [OpenNebula 7.0 Overview](https://docs.opennebula.io/7.0/getting_started/understand_opennebula/opennebula_concepts/opennebula_overview/)
- [OpenNebula 6.10 Front-end Installation](https://docs.opennebula.io/6.10/installation_and_configuration/frontend_installation/install.html)
- [OpenNebula 6.10 Front-end HA](https://docs.opennebula.io/6.10/installation_and_configuration/ha/frontend_ha.html)
- [OpenNebula 6.10 Database Setup](https://docs.opennebula.io/6.10/installation_and_configuration/frontend_installation/database.html)
- [OpenNebula 6.10 Monitoring Configuration](https://docs.opennebula.io/6.10/installation_and_configuration/opennebula_services/monitoring.html)
- [OpenNebula 6.0 Containerized Deployment](https://docs.opennebula.io/6.0/installation_and_configuration/containerized_deployment/architecture_deployment.html)

### Community Helm Charts (MEDIUM confidence - reference implementations)
- [kvaps/kube-opennebula](https://github.com/kvaps/kube-opennebula) - Most mature community chart
- [wedos/kube-opennebula](https://github.com/wedos/kube-opennebula) - Fork with production focus
- [ethz-hpc/k8s-OpenNebula](https://github.com/ethz-hpc/k8s-OpenNebula) - Academic deployment

### Docker Images (MEDIUM confidence)
- [opennebula/opennebula on Docker Hub](https://hub.docker.com/r/opennebula/opennebula) - Official image
- [kvaps/opennebula on Docker Hub](https://hub.docker.com/r/kvaps/opennebula) - Community image for Kubernetes

---
*Architecture research for: OpenNebula Helm Chart*
*Researched: 2026-01-23*

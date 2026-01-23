# Feature Research: OpenNebula Helm Chart

**Domain:** Cloud management platform containerization (OpenNebula on Kubernetes)
**Researched:** 2026-01-23
**Confidence:** MEDIUM (verified via official docs, existing Helm charts, and community implementations)

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = deployment is broken or unusable.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **oned (OpenNebula Daemon)** | Core service - nothing works without it | MEDIUM | Main daemon providing XML-RPC API, manages all resources. Must run as container with proper storage. |
| **Scheduler (mm_sched)** | VMs cannot be deployed without scheduling | LOW | Auto-starts with oned. Can run in same container or separate. |
| **Database Backend (MariaDB/MySQL)** | Persistence required - cloud state must survive restarts | MEDIUM | MariaDB preferred per project context. Needs PVC, backup strategy. SQLite not suitable for production. |
| **SSH Key Management** | Front-end must SSH to hypervisor nodes | MEDIUM | opennebula-ssh-agent service or alternative key distribution. Critical for node communication. |
| **Monitoring Subsystem (onemonitord)** | Hosts/VMs invisible without monitoring | LOW | Launched by oned. Gathers host status, VM metrics. |
| **Hook Execution Manager (HEM)** | Automation hooks won't work without it | LOW | Auto-starts with oned. Uses ZeroMQ for event publishing. |
| **CLI Tools (opennebula-tools)** | Operators need command-line management | LOW | onevm, onehost, onedatastore, etc. Include in image or sidecar. |
| **Persistent Storage (PVC)** | Cloud state must persist across restarts | MEDIUM | ReadWriteOnce for oned data, ReadWriteMany for VM logs/VNC tokens. |
| **Hypervisor Node Connectivity** | Must manage external KVM/LXC hosts | HIGH | SSH-based communication. Nodes need libvirtd, qemu-kvm, opennebula-node packages. |

### Differentiators (Competitive Advantage)

Features that set the Helm chart apart. Not required for basic operation, but valuable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Sunstone/FireEdge Web UI** | Visual management, user self-service | MEDIUM | FireEdge is next-gen UI replacing Ruby Sunstone. Port 2616. Optional but expected for usability. |
| **OneFlow (Multi-VM Services)** | Orchestrates application stacks as single units | MEDIUM | Manages service elasticity, auto-scaling. Port 2474. Requires OneGate for full functionality. |
| **OneGate (VM Communication)** | VMs can pull/push data to OpenNebula | MEDIUM | Enables contextualization, elasticity triggers from inside VMs. Port 5030. |
| **VNC/Guacamole Console Access** | Browser-based VM console | HIGH | Requires opennebula-guacd, FireEdge. Complex networking (WebSocket proxying). |
| **LDAP/AD Authentication** | Enterprise identity integration | MEDIUM | AUTH_MAD configuration. Supports LDAP, Active Directory, group mapping. |
| **High Availability (Multi-oned)** | Reduced downtime for management plane | HIGH | StatefulSet with leader election. Existing charts use leader label approach. |
| **Marketplace Integration** | Easy appliance import/export | LOW | Built into oned. Configure marketplace endpoints. DockerHub, Linux Containers supported. |
| **Showback/Billing** | Cost tracking per user/group | LOW | opennebula-showback.timer. Reports resource usage costs. |
| **Edge Cluster Provisioning** | Deploy remote clusters on-demand | HIGH | opennebula-provision package. Uses Terraform/Ansible internally. |
| **Ceph Storage Driver** | Distributed storage for VM disks | HIGH | Requires Ceph cluster, client configuration on nodes. RBD integration. |
| **Open vSwitch Networking** | Advanced VLAN/VXLAN/QinQ support | HIGH | Requires OVS on hypervisor nodes. Enables network isolation. |
| **noVNC Proxy** | Alternative to Guacamole for VNC | MEDIUM | opennebula-novnc service. Port 29876. Simpler than Guacamole. |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems in a containerized deployment.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Hypervisor nodes in containers** | "Everything in Kubernetes" appeal | KVM requires hardware virtualization, direct kernel access, privileged containers. Security nightmare. | Keep hypervisor nodes external to Kubernetes. Front-end containers manage external KVM/LXC hosts via SSH. |
| **SQLite database** | Simpler setup, no external DB | Not suitable for production, no HA, file locking issues in containers | Always use MariaDB/MySQL with proper PVC. |
| **All-in-one single container** | Simpler deployment | Scaling impossible, no HA, debugging difficult, upgrade complexity | Separate containers for oned, Sunstone, optional services. |
| **Enterprise Edition tools** | Better upgrade tooling | Commercial license required, not redistributable in public chart | Build for Community Edition. Users can swap images for EE. |
| **Built-in storage provisioning** | Kubernetes-native storage | OpenNebula manages its own datastores on hypervisor nodes. Mixing with Kubernetes storage creates confusion. | Document external datastore setup (Ceph, NFS) on hypervisor nodes, not via Kubernetes CSI. |
| **Embedding libvirt/QEMU** | Container-based hypervisor | Massive security surface, hardware passthrough complexity, kernel module requirements | External hypervisor nodes with proper libvirtd setup. |
| **Auto-provisioning Kubernetes nodes as hypervisors** | Use existing cluster compute | Kubernetes nodes are already scheduled; nested virt adds overhead and complexity | Use dedicated hypervisor nodes outside the Kubernetes cluster. |
| **Real-time VM migration within Kubernetes** | Kubernetes-native live migration | OpenNebula live migration is between hypervisor hosts, not pods | Document live migration between external KVM hosts. |

## Feature Dependencies

```
Core Dependencies (Must Have):
================================

oned (OpenNebula Daemon)
    |
    +---> MariaDB/MySQL (state persistence)
    |
    +---> Scheduler (mm_sched) [auto-starts with oned]
    |
    +---> Monitoring (onemonitord) [auto-starts with oned]
    |
    +---> HEM (Hook Execution Manager) [auto-starts with oned]
    |
    +---> SSH Agent / Key Distribution [required for node communication]


Optional Features Tree:
=======================

FireEdge (Web UI)
    |
    +---> Guacamole (opennebula-guacd) [for VNC/RDP/SSH console]
    |
    +---> Requires: oned API access

OneFlow (Multi-VM Services)
    |
    +---> Requires: oned API access
    |
    +---> Enhanced by: OneGate (for elasticity triggers from VMs)

OneGate (VM Communication)
    |
    +---> Requires: oned API access
    |
    +---> Enables: VM contextualization, elasticity rules

noVNC
    |
    +---> Alternative to: Guacamole
    |
    +---> Simpler but: Less features (no RDP/SSH)


Storage Drivers (on hypervisor nodes, not in container):
========================================================

Filesystem Datastore ---> NFS/Local storage
Ceph Datastore ---------> Requires Ceph cluster + client setup
iSCSI Datastore --------> Requires iSCSI target configuration


Networking Drivers (on hypervisor nodes):
=========================================

bridge -------------> Linux bridge (default, simple)
802.1Q VLAN --------> VLAN tagging
ovswitch -----------> Open vSwitch
ovswitch_vxlan -----> OVS + VXLAN overlay
```

### Dependency Notes

- **oned requires MariaDB/MySQL:** SQLite is not suitable for containerized production deployments.
- **Scheduler requires oned:** Starts automatically, shares container or separate deployment.
- **FireEdge enhances oned:** Provides web UI but oned is fully functional via CLI/API without it.
- **OneFlow requires OneGate:** For elasticity triggers from inside VMs; without OneGate, OneFlow still works but with reduced functionality.
- **Guacamole requires FireEdge:** Cannot run standalone; FireEdge acts as proxy.
- **Hypervisor drivers are node-side:** KVM/LXC drivers run on hypervisor nodes, not in the OpenNebula front-end container.

## MVP Definition

### Launch With (v1.0)

Minimum viable product - what's needed for a working OpenNebula deployment on Kubernetes.

- [x] **oned container** - Core daemon with scheduler, monitoring, HEM auto-starting
- [x] **MariaDB** - External or bundled (Bitnami chart) database
- [x] **Persistent storage** - PVC for /var/lib/one, shared PVC for logs/tokens
- [x] **SSH key management** - ConfigMap/Secret for SSH keys, or ssh-agent sidecar
- [x] **CLI tools** - Included in oned image for debugging
- [x] **Service exposure** - XML-RPC API (port 2633), optionally Sunstone (port 2616)
- [x] **Configuration management** - ConfigMaps for oned.conf, sched.conf

### Add After Validation (v1.x)

Features to add once core is working.

- [ ] **FireEdge/Sunstone** - Add when API-only management is insufficient; trigger: user feedback
- [ ] **OneGate** - Add when users need VM contextualization; trigger: VM-to-cloud communication requests
- [ ] **OneFlow** - Add when multi-VM service orchestration needed; trigger: complex application deployments
- [ ] **High Availability** - Add when single-point-of-failure is unacceptable; trigger: production requirements
- [ ] **LDAP Authentication** - Add when enterprise identity integration needed; trigger: multi-user deployments
- [ ] **Showback** - Add when cost tracking needed; trigger: multi-tenant/billing requirements

### Future Consideration (v2+)

Features to defer until product-market fit is established.

- [ ] **VNC/Guacamole console** - Complex WebSocket proxying; defer until web UI is stable
- [ ] **Edge Cluster Provisioning** - Requires Terraform/Ansible integration; defer until core is solid
- [ ] **Open vSwitch integration** - Node-side configuration; document but don't automate initially
- [ ] **Ceph storage automation** - Complex integration; document manual setup first

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| oned daemon | HIGH | MEDIUM | P1 |
| MariaDB integration | HIGH | LOW | P1 |
| Persistent storage | HIGH | LOW | P1 |
| SSH connectivity | HIGH | MEDIUM | P1 |
| CLI tools | MEDIUM | LOW | P1 |
| Sunstone/FireEdge | HIGH | MEDIUM | P2 |
| OneGate | MEDIUM | LOW | P2 |
| OneFlow | MEDIUM | MEDIUM | P2 |
| High Availability | HIGH | HIGH | P2 |
| LDAP auth | MEDIUM | MEDIUM | P2 |
| VNC console | MEDIUM | HIGH | P3 |
| Showback | LOW | LOW | P3 |
| Edge provisioning | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for launch (v1.0)
- P2: Should have, add when possible (v1.x)
- P3: Nice to have, future consideration (v2+)

## Competitor/Reference Analysis

| Feature | kvaps/kube-opennebula | wedos/kube-opennebula | Our Approach |
|---------|----------------------|----------------------|--------------|
| oned | StatefulSet, leader election | Fork of kvaps | StatefulSet with optional HA |
| Database | MySQL bundled | MySQL bundled | MariaDB (Bitnami chart) or external |
| Web UI | Sunstone (Ruby legacy) | Same | FireEdge (next-gen) preferred |
| Storage | RWO + RWX PVCs | Same | Same pattern, document requirements |
| Node mgmt | External nodes via SSH | Same | Same - external hypervisors only |
| Upgrades | Full reinstall for major | Same | Same (database migration) |
| Dockerfiles | Provided in repo | Same | Create optimized images |

### Gaps in Existing Charts

1. **No FireEdge support** - kvaps uses legacy Ruby Sunstone
2. **Outdated versions** - Chart version 1.2.0, OpenNebula has moved to 6.10/7.0
3. **Limited documentation** - Sparse README, no examples for common scenarios
4. **No HA documentation** - Leader election exists but poorly documented
5. **No LXC focus** - KVM-centric, LXC support unclear

### Our Differentiators

1. **FireEdge-first** - Modern web UI from the start
2. **Current versions** - Target OpenNebula 6.10 or 7.0
3. **Comprehensive docs** - Usage examples, troubleshooting
4. **Explicit LXC support** - Document both KVM and LXC hypervisor setup
5. **Modular design** - Clear separation of optional features

## Sources

### Official Documentation (HIGH confidence)
- [OpenNebula Overview 6.10](https://docs.opennebula.io/6.10/overview/opennebula_concepts/opennebula_overview.html)
- [OpenNebula Overview 7.0](https://docs.opennebula.io/7.0/getting_started/understand_opennebula/opennebula_concepts/opennebula_overview/)
- [Single Front-end Installation](https://docs.opennebula.io/6.10/installation_and_configuration/frontend_installation/install.html)
- [oned Configuration](https://docs.opennebula.io/6.10/installation_and_configuration/opennebula_services/oned.html)
- [Cloud Architecture Design](https://docs.opennebula.io/6.10/overview/cloud_architecture_and_design/cloud_architecture_design.html)
- [KVM Driver](https://docs.opennebula.io/7.0/product/operation_references/hypervisor_configuration/kvm_driver/)
- [LDAP Authentication](https://docs.opennebula.io/7.0/product/cloud_system_administration/authentication_configuration/ldap/)
- [Advanced SSH Usage](https://docs.opennebula.io/7.0/product/control_plane_configuration/large-scale_deployment/advanced_ssh_usage/)
- [Using Hooks](https://docs.opennebula.io/7.0/product/integration_references/system_interfaces/hook_driver/)
- [Open vSwitch Networks](https://docs.opennebula.io/6.10/open_cluster_deployment/networking_setup/openvswitch.html)
- [Ceph Datastore](https://docs.opennebula.io/7.0/product/cluster_configuration/storage_system/ceph_ds/)

### Existing Helm Charts (MEDIUM confidence)
- [kvaps/kube-opennebula](https://github.com/kvaps/kube-opennebula) - Reference implementation
- [wedos/kube-opennebula](https://github.com/wedos/kube-opennebula) - Fork with customizations

### Community Discussions (LOW confidence - verify specific claims)
- [OpenNebula Community Forum](https://forum.opennebula.io/)
- [GitHub Issues](https://github.com/OpenNebula/one/issues)

---
*Feature research for: OpenNebula Helm Chart*
*Researched: 2026-01-23*

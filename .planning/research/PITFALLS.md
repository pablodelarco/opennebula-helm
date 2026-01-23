# Pitfalls Research: OpenNebula Containerization

**Domain:** Cloud management platform containerization (OpenNebula on Kubernetes)
**Researched:** 2026-01-23
**Confidence:** MEDIUM (multiple sources cross-referenced, some items from single sources)

## Critical Pitfalls

### Pitfall 1: Systemd Dependency Prevents Docker Compatibility

**What goes wrong:**
OpenNebula services are packaged as systemd units. Systemd cannot run inside standard Docker containers, only in Podman. This means official OpenNebula container images only work with Podman, not Docker/Kubernetes.

**Why it happens:**
OpenNebula's packaging assumes a traditional systemd-based Linux environment. The official containerized deployment was designed for Podman, not for Kubernetes.

**How to avoid:**
- Use supervisord or another process manager instead of systemd
- Build custom images that start services directly without systemd
- The kube-opennebula project uses this approach - study their image architecture
- Consider runit as an alternative init system (mentioned as future direction by onedocker maintainer)

**Warning signs:**
- Container crashes immediately after start
- Logs show systemd PID 1 issues
- Services fail to start with "systemctl" errors

**Phase to address:**
Phase 1 (Docker Image Foundation) - Must be solved before any Kubernetes deployment is possible.

**Sources:**
- [OpenNebula Containerized Deployment Reference](https://docs.opennebula.io/6.0/installation_and_configuration/containerized_deployment/reference.html)
- [ospalax/onedocker GitHub](https://github.com/ospalax/onedocker)

---

### Pitfall 2: SSH Key Management Across Restarts

**What goes wrong:**
OpenNebula generates SSH key pairs on first start for communication between frontend and hypervisor nodes. If the container restarts without persisting `/var/lib/one/.ssh/`, new keys are generated and all node connections break.

**Why it happens:**
Developers assume ephemeral containers will retain state, or forget that SSH keys must match between frontend and all registered hypervisor nodes.

**How to avoid:**
- Mount `/var/lib/one/.ssh/` as a persistent volume
- Pre-generate SSH keys and inject them via secrets
- Include SSH key persistence in the Helm chart values (auto_ssh secret management)
- Document the key distribution process to hypervisor nodes

**Warning signs:**
- Hosts show as "ERROR" state after pod restart
- "Host key verification failed" errors in logs
- "Permission denied (publickey)" when deploying VMs

**Phase to address:**
Phase 1 (Docker Image) - Design for key persistence from the start.
Phase 3 (Helm Chart) - Implement proper secret management for SSH keys.

**Sources:**
- [OpenNebula Advanced Deployment Customizations](https://docs.opennebula.io/6.0/installation_and_configuration/containerized_deployment/custom.html)
- [kvaps/kube-opennebula](https://github.com/kvaps/kube-opennebula)

---

### Pitfall 3: Database Choice and Persistence

**What goes wrong:**
SQLite is the default but unsuitable for production. Database files not persisted lead to complete state loss. MySQL/MariaDB external dependency complicates deployment.

**Why it happens:**
SQLite works fine for testing and appears to work until load increases or container restarts occur.

**How to avoid:**
- Default to MySQL/MariaDB in production configurations
- Require explicit SQLite opt-in only for development/testing
- Mount database storage as PersistentVolumeClaim with `Retain` reclaim policy
- Document database backup procedures before any upgrade

**Warning signs:**
- Slow response times under load (SQLite limitation)
- "Database is locked" errors
- Complete state loss after pod recreation

**Phase to address:**
Phase 1 (Docker Image) - Support both SQLite and MySQL backends.
Phase 3 (Helm Chart) - Default to MySQL with operator or external database support.

**Sources:**
- [OpenNebula Database Setup Documentation](https://docs.opennebula.io/6.8/installation_and_configuration/frontend_installation/database.html)

---

### Pitfall 4: Major Version Upgrades Require Full Reinstall

**What goes wrong:**
Rolling updates don't work for major OpenNebula version upgrades. Database migrations require specific procedures. Helm upgrade breaks the deployment.

**Why it happens:**
OpenNebula's database schema changes between major versions require explicit migration steps that can't happen during rolling updates.

**How to avoid:**
- Document that major upgrades require: stop all pods, backup database, uninstall chart, install new version
- Implement pre-upgrade hooks that verify database state
- New images perform database migration on first start - ensure this is tested
- Never skip backup before upgrade

**Warning signs:**
- `onedb upgrade` errors during pod startup
- Database version mismatch errors
- VMs in inconsistent states after upgrade

**Phase to address:**
Phase 3 (Helm Chart) - Document upgrade procedures clearly.
Phase 4 (Production Readiness) - Test upgrade paths thoroughly.

**Sources:**
- [kvaps/kube-opennebula](https://github.com/kvaps/kube-opennebula)
- [OpenNebula Forum - DB Upgrade Issues](https://forum.opennebula.io/t/db-upgrade-community-6-0-0-to-6-2-0/10099)

---

### Pitfall 5: Privileged Container Requirements

**What goes wrong:**
OpenNebula containers require privileged mode for various operations (FUSE mounts for marketplaces, libvirt access). Running unprivileged causes silent failures.

**Why it happens:**
OpenNebula needs capabilities like SYS_ADMIN for FUSE mounts (Docker Hub marketplace integration) and access to host resources.

**How to avoid:**
- Document the specific capabilities required (SYS_ADMIN at minimum)
- For Kubernetes, use appropriate securityContext settings
- If AppArmor is enabled on Ubuntu/Debian, run with unconfined profile or disable
- Test marketplace integrations specifically

**Warning signs:**
- Docker Hub/Linux Containers marketplace images fail to download
- "Permission denied" errors for FUSE operations
- Marketplace browser shows empty or errors

**Phase to address:**
Phase 1 (Docker Image) - Document required capabilities.
Phase 3 (Helm Chart) - Configure appropriate securityContext.

**Sources:**
- [OpenNebula Troubleshooting Reference](https://docs.opennebula.io/6.0/installation_and_configuration/containerized_deployment/reference.html)

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Using SQLite for "simplicity" | No external database dependency | Performance issues, no HA support | Development/testing only |
| Hardcoded QEMU paths | Works on one distro | Breaks heterogeneous hypervisor environments | Never for production |
| Skipping SSH key persistence | Faster initial setup | All node connections break on restart | Never |
| Single-container deployment | Simpler architecture | No scalability, harder to debug | Learning/evaluation only |
| Ignoring AppArmor/SELinux | Fewer permission issues | Security vulnerabilities, unpredictable failures | Never in production |

---

## Integration Gotchas

Common mistakes when connecting OpenNebula to external services.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Hypervisor Nodes | Not distributing SSH public key to nodes | Automate key distribution or use pre-shared keys |
| MySQL Database | Special characters in password break `onedb` | Use alphanumeric passwords or proper escaping |
| Storage (Ceph) | Mixing Ceph with shared NFS datastores | Avoid mixing; if required, understand migration limitations |
| VNC/SPICE Console | FireEdge endpoints misconfigured | Configure both private and public endpoints correctly |
| OneGate/OneFlow | Services not started on fresh deployment | Explicitly enable and configure in deployment |
| Docker Hub Marketplace | oneadmin user lacks docker permissions | Add oneadmin to docker group, or run frontend as root |

---

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| SQLite database | Slow queries, database locks | Use MySQL/MariaDB | 10+ concurrent VMs |
| SSH transfer mode for images | Long deployment times | Use shared storage | 50+ VMs |
| Single oned instance | Bottleneck on API calls | Multi-container with load balancing | 100+ VMs |
| Local storage only | No live migration | Configure shared storage (NFS/Ceph) | Any HA requirement |
| Default QEMU settings | Suboptimal VM performance | Tune CPU pinning, huge pages | Performance-sensitive workloads |

---

## Security Mistakes

Domain-specific security issues beyond general container security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Running frontend as root unnecessarily | Container escape risks | Use oneadmin user, only root for Docker Hub marketplace |
| Exposing oned API without TLS | Credential interception | Configure TLS for all API endpoints |
| Default serveradmin password | Unauthorized access | Change all default passwords on first deployment |
| SSH keys without passphrase in secrets | Key theft if secrets leaked | Consider SSH agent forwarding, or accept risk with proper RBAC |
| AppArmor disabled entirely | Reduced security posture | Use custom AppArmor profile instead of unconfined |
| Storing credentials in ConfigMaps | Credentials exposed in plain text | Use Kubernetes Secrets with encryption at rest |

---

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **VNC Console:** Often missing FireEdge configuration - verify VNC works from Sunstone
- [ ] **Live Migration:** Works locally but fails in production - verify SSH bidirectional access between all nodes
- [ ] **Marketplace Integration:** Appears configured but FUSE permissions missing - test actual image download
- [ ] **HA Setup:** Raft configured but monitord MONITOR_ADDRESS still "auto" - must be virtual IP
- [ ] **OneGate Service:** Config exists but service not running - verify `oneflow` and `onegate` services started
- [ ] **Storage Transfer Mode:** Datastore created but mode incompatible - verify image datastore supports system datastore transfer mode
- [ ] **Database Backup:** Assumes auto-backup, but no backup job configured - implement explicit backup CronJob
- [ ] **Upgrade Path:** Chart version bumped but database migration not tested - always test upgrades in staging

---

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| SSH key regeneration | MEDIUM | Export new public key, redistribute to all nodes, verify connectivity |
| Database corruption | HIGH | Restore from backup, run `onedb fsck`, may require manual VM state cleanup |
| Major version upgrade failure | HIGH | Restore database backup, reinstall previous version, retry with proper procedure |
| Lost persistent volumes | CRITICAL | Restore from backup (if exists), or rebuild entire deployment |
| Node connection failures | LOW | Check SSH, redistribute keys, re-add hosts to OpenNebula |
| Marketplace FUSE failures | LOW | Add SYS_ADMIN capability, configure AppArmor unconfined, restart |

---

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Systemd dependency | Phase 1: Docker Image | Container starts and runs services without systemd |
| SSH key persistence | Phase 1 + Phase 3 | Pod restart retains SSH connectivity to test node |
| Database persistence | Phase 1 + Phase 3 | Pod restart retains all VM/host state |
| QEMU path hardcoding | Phase 1 | Test with both Debian and RHEL-based hypervisors |
| Privileged container requirements | Phase 3 | Marketplace image download works |
| Major version upgrades | Phase 4 | Document and test upgrade from N to N+1 |
| VNC console configuration | Phase 3 | VNC access works from Sunstone UI |
| OneGate/OneFlow | Phase 3 | Services start automatically, API accessible |
| Transfer mode compatibility | Phase 3 | VM deployment works with configured datastores |

---

## OpenNebula-Specific Port Gotchas

Internal ports that cannot be easily changed.

| Port | Service | Constraint |
|------|---------|------------|
| 2633 | oned (API) | Configurable but must match all clients |
| 2634 | oned (VNC proxy) | Hardwired internally |
| 4124 | monitord | External AND internal port must match |
| 5030 | OneGate | Must be accessible from VMs |
| 2474 | OneFlow | Internal service communication |
| 2616 | FireEdge | VNC/SPICE proxy |
| 9869 | Sunstone | Web UI |

**Warning:** For monitord and VNC ports, changing only the external (published) port while keeping internal port different will cause failures. Both must match.

---

## Sources

**Official Documentation:**
- [OpenNebula Containerized Deployment](https://docs.opennebula.io/6.0/installation_and_configuration/containerized_deployment/)
- [OpenNebula Database Setup](https://docs.opennebula.io/6.8/installation_and_configuration/frontend_installation/database.html)
- [OpenNebula Upgrading Guide](https://docs.opennebula.io/6.8/intro_release_notes/upgrades/upgrading_single.html)

**Community Projects:**
- [kvaps/kube-opennebula](https://github.com/kvaps/kube-opennebula) - Existing Helm chart with documented gotchas
- [wedos/kube-opennebula](https://github.com/wedos/kube-opennebula) - Fork with additional learnings
- [ospalax/onedocker](https://github.com/ospalax/onedocker) - Podman-based deployment with systemd workaround insights

**Forum Discussions:**
- [OpenNebula Forum - Container Deployment Issues](https://forum.opennebula.io/)
- [OpenNebula Forum - SSH Key Changes](https://forum.opennebula.io/t/on-cant-deploy-or-monitor-a-host-after-the-ssh-key-of-the-sunstone-node-was-changed/6281)
- [OpenNebula Forum - VNC Issues](https://forum.opennebula.io/t/cant-connect-to-vnc-server-with-sunstone-and-fireedge/11532)

**GitHub Issues:**
- [OpenNebula GitHub Issues](https://github.com/OpenNebula/one/issues)
- [QEMU Emulator Detection Issue](https://github.com/OpenNebula/one/issues/5167)

---
*Pitfalls research for: OpenNebula Helm Chart on Kubernetes*
*Researched: 2026-01-23*

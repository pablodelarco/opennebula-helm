# Project Research Summary

**Project:** OpenNebula Helm Chart for Kubernetes
**Domain:** Cloud Management Platform Containerization
**Researched:** 2026-01-23
**Confidence:** HIGH

## Executive Summary

OpenNebula is a mature private cloud management platform that orchestrates virtual machines across hypervisor nodes. Experts containerize OpenNebula by running the **control plane** (oned, FireEdge UI, OneFlow/OneGate) in Kubernetes while managing **external KVM/LXC hypervisor hosts** via SSH. This is not a traditional microservices architecture - it's a management plane orchestrating bare-metal infrastructure.

The recommended approach is to build a Helm chart with a modular design: start with a core MVP (oned + MariaDB + persistent storage), add the modern FireEdge web UI, then layer in optional services (OneFlow, OneGate). Use Ubuntu 24.04 LTS as the base image with official OpenNebula 6.10 LTS packages. The critical architectural constraint is that hypervisors must remain external to Kubernetes - attempting to run KVM/LXC inside containers leads to security nightmares and defeats container isolation.

The primary risk is the systemd dependency: official OpenNebula packages assume systemd which doesn't run in standard Docker containers. This requires custom images using supervisord or similar process managers (the kvaps/kube-opennebula project has solved this). Secondary risks include SSH key persistence across restarts and database choice - SQLite is default but unsuitable for production. Address these in Phase 1 to avoid painful rebuilds later.

## Key Findings

### Recommended Stack

OpenNebula containerization requires glibc-based distributions, making Ubuntu 24.04 LTS the optimal choice over Alpine (musl incompatibilities) or Debian (larger image). The stack centers on OpenNebula 6.10 LTS with official packages, MariaDB (not SQLite) for production, and FireEdge as the modern web UI replacing legacy Sunstone.

**Core technologies:**
- **Ubuntu 24.04 LTS**: Base image - officially supported, smaller than Debian, glibc-compatible with OpenNebula packages, LTS support until 2034
- **OpenNebula 6.10 LTS**: Cloud platform - latest LTS with FireEdge UI, Prometheus monitoring included, active maintenance through 2026+
- **MariaDB 10.11+**: Database - required for production (SQLite only for dev/test), HA-capable, Bitnami subchart integration
- **Docker BuildKit**: Build system - cache mounts for faster rebuilds, multi-arch support (amd64/arm64)
- **supervisord/runit**: Process manager - replaces systemd for Docker compatibility (critical for Kubernetes deployment)

**Critical insight from STACK.md**: OpenNebula 7.x exists but 6.10 LTS is recommended for production stability and community knowledge base. The existing user Dockerfile uses Ubuntu 22.04 which works, but 24.04 provides longer support.

### Expected Features

OpenNebula deployments divide into table stakes (required for basic operation), differentiators (competitive advantages), and anti-features (commonly requested but problematic).

**Must have (table stakes):**
- **oned daemon**: Core service providing XML-RPC API, VM/network/storage management - nothing works without it
- **MariaDB/MySQL**: Persistent state storage - SQLite not suitable for production
- **SSH key management**: Front-end must connect to external hypervisor nodes via SSH
- **Scheduler (mm_sched)**: Auto-starts with oned, assigns VMs to hosts
- **Monitoring (onemonitord)**: Gathers host/VM metrics, required for visibility
- **Persistent storage (PVC)**: State must survive pod restarts

**Should have (competitive):**
- **FireEdge web UI**: Modern React-based UI replacing legacy Sunstone, required for usability
- **OneFlow**: Multi-VM service orchestration for complex application stacks
- **OneGate**: VM-to-OpenNebula communication for contextualization and elasticity
- **VNC console access**: Browser-based VM console via Guacamole (complex WebSocket proxying)
- **LDAP/AD authentication**: Enterprise identity integration

**Defer (v2+):**
- **High Availability**: Multi-oned with leader election - complex, defer until single-replica works
- **Edge cluster provisioning**: Uses Terraform/Ansible internally, advanced use case
- **Showback/billing**: Cost tracking, low user demand initially

**Anti-features to avoid:**
- **Hypervisor nodes in containers**: KVM requires hardware virtualization and kernel access, security nightmare
- **SQLite in production**: File locking issues, no HA, performance problems beyond 10 VMs
- **All-in-one container**: Prevents scaling and HA, makes debugging difficult

**Feature dependency insight from FEATURES.md**: OneFlow requires OneGate for full elasticity functionality. FireEdge requires working oned API. VNC console requires both FireEdge and Guacamole. Start with oned+MariaDB, add FireEdge, then optional services.

### Architecture Approach

OpenNebula follows a control plane/data plane separation where Kubernetes hosts the control plane (oned, UI, orchestration services) while external bare-metal servers act as hypervisors. Communication flows via SSH from oned to hypervisor nodes, while monitoring data flows back via TCP/UDP on port 4124.

**Major components:**
1. **oned (StatefulSet)** - Core daemon with auto-starting scheduler/monitoring, requires stable network identity for SSH and HA
2. **MariaDB (Subchart)** - Database backend with persistent storage, single point of truth for cloud state
3. **FireEdge (Deployment)** - Stateless web UI, horizontally scalable, WebSocket support for VNC
4. **OneFlow (Deployment)** - Optional multi-VM orchestration service
5. **OneGate (Deployment)** - Optional VM communication gateway, must be reachable from VMs

**Data flow pattern**: User requests flow through FireEdge/CLI to oned's XML-RPC API. oned validates requests, persists state to MariaDB, and the scheduler assigns VMs to hosts. oned then SSHs to the selected hypervisor node to trigger VM creation via libvirtd. Monitoring flows in reverse: probe agents on hypervisor nodes push metrics to onemonitord (port 4124) which updates oned's database.

**Helm chart structure**: Organize templates by component (oned/, fireedge/, oneflow/, onegate/) rather than by resource type. This modular structure allows optional services to be enabled/disabled via values.yaml and matches the logical architecture.

**Critical constraint from ARCHITECTURE.md**: Hypervisors cannot run in Kubernetes. They must be external bare-metal/VM hosts with libvirtd, qemu-kvm, and proper networking. The containerized control plane orchestrates these external resources via SSH - this is fundamentally different from typical cloud-native architectures.

### Critical Pitfalls

Research identified five critical pitfalls that must be addressed in early phases to avoid project failure:

1. **Systemd dependency prevents Docker compatibility** - OpenNebula packages assume systemd which cannot run in standard containers. Use supervisord/runit instead. Address in Phase 1 (Docker image foundation) - without this, no Kubernetes deployment is possible. Warning signs: container crashes on start, systemctl errors in logs.

2. **SSH key management across restarts** - OpenNebula generates SSH keys on first start. If `/var/lib/one/.ssh/` isn't persisted, new keys are generated on restart and all hypervisor connections break. Mount as PersistentVolume or pre-generate and inject via secrets. Address in Phase 1 (design for persistence) and Phase 3 (Helm chart secret management). Warning signs: hosts show ERROR state after pod restart, "Permission denied (publickey)" errors.

3. **Database choice and persistence** - SQLite is default but unsuitable for production (file locking, no HA). Database files must be persisted or complete state loss occurs. Default to MariaDB with PVC and Retain policy. Address in Phase 1 (support both backends) and Phase 3 (default to MariaDB). Warning signs: "Database is locked" errors, slow response under load, state loss after pod recreation.

4. **Major version upgrades require full reinstall** - Rolling updates don't work for major OpenNebula versions. Database schema changes require explicit migration. Document that upgrades need: stop pods, backup DB, uninstall chart, install new version. Address in Phase 4 (document and test upgrade paths). Warning signs: `onedb upgrade` errors, database version mismatches.

5. **Privileged container requirements** - OpenNebula needs SYS_ADMIN capability for FUSE mounts (marketplace integration). Document required capabilities and configure appropriate securityContext. Address in Phase 1 (document capabilities) and Phase 3 (Helm chart securityContext). Warning signs: marketplace downloads fail, "Permission denied" for FUSE operations.

**Additional gotchas from PITFALLS.md**: Port 4124 (monitoring) requires external AND internal port to match - changing only external breaks monitoring. OneGate/OneFlow services often configured but not actually started. VNC console appears configured but FireEdge endpoints incorrect.

## Implications for Roadmap

Based on combined research, I recommend a 4-phase approach that addresses dependencies, avoids pitfalls, and delivers incremental value.

### Phase 1: Docker Image Foundation
**Rationale:** Must solve systemd incompatibility and establish container patterns before any Kubernetes work. The official OpenNebula images only work with Podman, not Docker/Kubernetes.

**Delivers:** Working Docker image that starts oned without systemd, uses supervisord or runit for process management, supports both SQLite (dev) and MariaDB (prod).

**Addresses:**
- Systemd dependency pitfall (Critical #1)
- SSH key persistence design (Critical #2)
- Database backend support (Critical #3)
- Proper Ubuntu 24.04 base with OpenNebula 6.10 packages
- BuildKit optimization with cache mounts

**Avoids:**
- All-in-one container anti-pattern - design for service separation from start
- Alpine base image (glibc incompatibility)
- Baking secrets into image

**Research flag:** LOW - well-documented by kvaps/kube-opennebula project, existing Dockerfile reference, clear patterns.

---

### Phase 2: Helm Chart Core (MVP)
**Rationale:** Establish Kubernetes deployment patterns with minimal viable product. Focus on getting oned running reliably before adding UI layers.

**Delivers:** Helm chart that deploys oned StatefulSet, MariaDB subchart, PersistentVolumeClaims, ConfigMaps for oned.conf, Secret management for SSH keys.

**Addresses:**
- oned daemon (table stakes)
- MariaDB integration (table stakes)
- Persistent storage for state and SSH keys (Critical #2)
- SSH key management via Kubernetes secrets
- Basic CLI access for testing

**Implements:**
- StatefulSet pattern for oned (stable network identity)
- Bitnami MariaDB subchart dependency
- PVC for /var/lib/one (RWO) and /var/lib/one/datastores (RWX if needed)
- ConfigMap templating for oned.conf, sched.conf, monitord.conf
- Secret for oneadmin credentials and SSH keys

**Avoids:**
- SQLite anti-pattern (Critical #3)
- Hardcoded credentials anti-pattern

**Research flag:** LOW - standard Helm patterns, MariaDB subchart well-documented, existing kube-opennebula reference.

---

### Phase 3: Web UI and Optional Services
**Rationale:** With stable core, add FireEdge UI for usability and optional services (OneFlow/OneGate) for advanced features. This phase makes the system practically usable.

**Delivers:** FireEdge deployment with Ingress, optional OneFlow/OneGate deployments, VNC console support, proper securityContext for marketplace access.

**Addresses:**
- FireEdge web UI (competitive advantage, high user value)
- OneFlow/OneGate (competitive advantage)
- VNC console access (complex WebSocket proxying)
- Privileged container requirements (Critical #5)
- Ingress configuration for external access

**Implements:**
- FireEdge Deployment (stateless, horizontally scalable)
- Ingress resource with TLS support
- Optional OneFlow/OneGate deployments (enabled via values.yaml)
- SecurityContext with SYS_ADMIN capability where needed
- ConfigMaps for fireedge-server.conf, oneflow-server.conf, onegate-server.conf

**Avoids:**
- VNC "looks done but isn't" gotcha - verify actual VNC access works
- OneGate/OneFlow configured but not started gotcha

**Research flag:** MEDIUM - FireEdge configuration needs validation, VNC/Guacamole integration complex, WebSocket proxying may need research. Consider `/gsd:research-phase` for VNC console specifically.

---

### Phase 4: Production Readiness
**Rationale:** After core functionality works, address operational concerns: upgrades, monitoring, documentation, testing. This makes the chart production-grade.

**Delivers:** Upgrade documentation, backup/restore procedures, monitoring integration, comprehensive README with examples, tested upgrade paths, security hardening.

**Addresses:**
- Major version upgrade pitfall (Critical #4)
- Security mistakes (TLS, default passwords, RBAC)
- Performance tuning (scheduler intervals, monitoring intervals)
- HA consideration (document requirements, optional implementation)

**Implements:**
- Pre-upgrade hooks for validation
- Backup CronJob for MariaDB
- Prometheus ServiceMonitor resources
- RBAC for least-privilege access
- Network policies for security
- Comprehensive values.yaml documentation
- Troubleshooting guide

**Avoids:**
- "Looks done but isn't" checklist items
- Upgrade path testing gap
- Database backup assumption gap

**Research flag:** LOW - operational patterns well-established, upgrade procedures documented by OpenNebula, monitoring integrations standard.

---

### Phase Ordering Rationale

1. **Phase 1 before Phase 2**: Cannot deploy to Kubernetes without Docker-compatible images. Systemd dependency is a blocking issue.

2. **Phase 2 before Phase 3**: UI/optional services are useless without stable oned core. Database persistence and SSH keys must work reliably first.

3. **Phase 3 before Phase 4**: Production hardening requires a working system to test against. Upgrade paths need something to upgrade from.

4. **Deferred to post-v1.0**: High Availability (complex Raft consensus, requires 3-5 replicas, shared filesystem, floating IP), Edge cluster provisioning (niche use case, Terraform/Ansible complexity).

**Dependency chain**: Docker image → StatefulSet + MariaDB → FireEdge UI → OneFlow/OneGate → HA/observability. Each phase builds on previous phase outputs.

**Pitfall mitigation strategy**: Address Critical #1 (systemd) in Phase 1, Critical #2-3 (SSH keys, database) in Phases 1-2, Critical #5 (privileges) in Phase 3, Critical #4 (upgrades) in Phase 4.

### Research Flags

**Phases needing deeper research during planning:**
- **Phase 3 (VNC console)**: WebSocket proxying through Ingress, Guacamole integration with FireEdge, complex networking. Use `/gsd:research-phase` to investigate: "How do experts configure VNC console access through Kubernetes ingress for OpenNebula FireEdge?"

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (Docker image)**: Well-documented by kvaps/kube-opennebula, clear supervisord patterns, existing reference Dockerfiles.
- **Phase 2 (Helm core)**: Standard StatefulSet + subchart pattern, extensive Kubernetes documentation, similar to many database-backed applications.
- **Phase 4 (production)**: Standard operational practices, OpenNebula upgrade docs comprehensive, monitoring integrations follow established patterns.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Official OpenNebula docs verify Ubuntu 24.04/22.04 support, OpenNebula 6.10 LTS active, existing implementation validates choices |
| Features | HIGH | Official docs clearly define required components (oned, scheduler, monitoring), existing Helm charts confirm feature priorities |
| Architecture | HIGH | Official containerized deployment docs describe control plane/hypervisor separation, kvaps implementation validates patterns |
| Pitfalls | MEDIUM | Systemd issue confirmed by multiple sources (ospalax/onedocker, kvaps), SSH/database issues from forum posts and GitHub issues, some inference from similar systems |

**Overall confidence:** HIGH

Research is comprehensive with official documentation as primary source, validated by multiple community implementations (kvaps, wedos, ethz-hpc). Lower confidence on pitfalls reflects that some are inferred from general containerization experience rather than OpenNebula-specific documentation.

### Gaps to Address

**Gaps identified during research:**

1. **FireEdge VNC configuration specifics**: Official docs describe VNC functionality but lack detailed Kubernetes networking examples. Address during Phase 3 planning with targeted research on WebSocket proxying patterns.

2. **High Availability implementation details**: HA docs describe Raft consensus requirements but existing Helm charts use simpler leader election. Defer detailed HA research until Phase 4 or post-v1.0, document single-replica limitations for v1.0.

3. **LXC vs KVM hypervisor differences**: Research focused on KVM (more common), LXC support mentioned but less documented. Validate LXC-specific considerations when first user requests it.

4. **Multi-arch build testing**: Recommendation includes arm64 support but research didn't verify OpenNebula 6.10 packages available for arm64. Validate during Phase 1 or scope to amd64-only initially.

5. **MariaDB subchart version compatibility**: Bitnami MariaDB chart evolves rapidly. Pin specific chart version during Phase 2 and test compatibility with OpenNebula database requirements.

**How to handle gaps:**
- VNC configuration: Use `/gsd:research-phase` during Phase 3 planning
- HA implementation: Document as "future work" in v1.0, revisit based on user demand
- LXC support: Document as "community tested" rather than "officially supported"
- Multi-arch: Start with amd64-only, add arm64 after x86 validation
- MariaDB version: Conservative pinning strategy, test before updates

## Sources

### Primary (HIGH confidence)
- [OpenNebula 6.10 Official Documentation](https://docs.opennebula.io/6.10/) - Platform notes, installation guides, service configuration
- [OpenNebula 7.0 Official Documentation](https://docs.opennebula.io/7.0/) - Architecture concepts, driver references
- [Docker Documentation](https://docs.docker.com/) - Multi-stage builds, BuildKit cache optimization
- [GitHub Actions Documentation](https://docs.github.com/actions) - CI/CD patterns for container builds
- [kvaps/kube-opennebula](https://github.com/kvaps/kube-opennebula) - Reference Helm chart implementation, solves systemd issue

### Secondary (MEDIUM confidence)
- [wedos/kube-opennebula](https://github.com/wedos/kube-opennebula) - Production-focused fork with operational insights
- [ospalax/onedocker](https://github.com/ospalax/onedocker) - Podman-based deployment, systemd workaround insights
- [OpenNebula Community Forum](https://forum.opennebula.io/) - SSH key issues, VNC configuration problems, DB upgrade discussions
- [OpenNebula GitHub Issues](https://github.com/OpenNebula/one/issues) - QEMU path detection issue, various bug reports

### Tertiary (LOW confidence)
- [ethz-hpc/k8s-OpenNebula](https://github.com/ethz-hpc/k8s-OpenNebula) - Academic deployment, limited documentation
- [JFrog Ubuntu vs Alpine Article](https://jfrog.com/learn/cloud-native/docker-ubuntu-base-image/) - Base image comparison
- Community blog posts and Stack Overflow discussions - Verified against official docs before inclusion

---
*Research completed: 2026-01-23*
*Ready for roadmap: yes*

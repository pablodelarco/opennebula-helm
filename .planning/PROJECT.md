# OpenNebula Helm Chart

## What This Is

A public Helm chart for deploying OpenNebula on Kubernetes, backed by a custom Docker image that automatically updates when new OpenNebula Community versions are released. Designed to work for both homelab experimentation and production deployments.

## Core Value

A production-ready, self-updating OpenNebula deployment on Kubernetes that the community can use out of the box.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Docker image containing OpenNebula components (architecture TBD after research)
- [ ] GitHub Actions pipeline that detects new OpenNebula releases and rebuilds the image
- [ ] Docker image published to Docker Hub (pablodelarco namespace)
- [ ] Helm chart that deploys OpenNebula on Kubernetes
- [ ] MariaDB bundled as subchart dependency
- [ ] Support for KVM/QEMU hypervisor management
- [ ] Support for LXC container management
- [ ] Works on homelab clusters
- [ ] Production-ready configuration options

### Out of Scope

- VMware/ESXi integration — not needed, focus on KVM/LXC
- Paid OpenNebula Enterprise features — community edition only
- Multi-cloud provider integrations — keep scope focused

## Context

**Prior work:**
- Docker image: pablodelarco/opennebula-frontend on Docker Hub (OpenNebula 6.10)
- GitHub repo: https://github.com/pablodelarco/docker_opennebula — contains Dockerfile, Helm chart, and CI workflow that can be upgraded/reused

**Research completed:** OpenNebula architecture analyzed. Key findings:
- oned is the central daemon; scheduler/monitoring auto-start with it
- Hypervisors (KVM/LXC) CANNOT run in Kubernetes — control plane only
- Systemd dependency solved by manual service starts in entrypoint (existing pattern works)
- MariaDB required for production (SQLite doesn't support concurrent writes)
- SSH key persistence is critical for hypervisor communication

**Target version:** OpenNebula 7.0 (latest)

**Target environments:**
- Homelab Kubernetes clusters (like kubernetes-homelab)
- Production Kubernetes deployments

**Distribution:**
- Docker image: Docker Hub (pablodelarco/opennebula-frontend)
- Helm chart: Public Helm repository (method TBD)

## Constraints

- **Tech stack**: Helm 3, Docker, GitHub Actions
- **Base image**: Must work with OpenNebula Community Edition (open source)
- **Hypervisors**: KVM/QEMU and LXC only
- **Database**: MariaDB (bundled via subchart)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Public project from start | User wants community adoption | — Pending |
| MariaDB as subchart | SQLite doesn't support concurrent writes; MariaDB is standard | ✓ Good |
| OpenNebula 7.0 (not 6.10 LTS) | User wants latest version | — Pending |
| Control plane only | Hypervisors require hardware virtualization, can't run in K8s | ✓ Good |
| Manual service starts | Avoids systemd dependency; existing pattern proven | ✓ Good |
| Upgrade existing repo | https://github.com/pablodelarco/docker_opennebula has good foundation | — Pending |

---
*Last updated: 2025-01-23 after requirements definition*

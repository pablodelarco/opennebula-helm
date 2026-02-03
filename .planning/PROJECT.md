# OpenNebula Helm Chart

## What This Is

A production-ready Helm chart for deploying OpenNebula on Kubernetes, backed by a custom Docker image that automatically updates when new OpenNebula Community versions are released. Includes complete CI/CD automation, MariaDB integration, and production hardening for hypervisor communication.

## Core Value

A production-ready, self-updating OpenNebula deployment on Kubernetes that the community can use out of the box.

## Current State

**Shipped:** v1.1 Production Hardening (2026-02-03)

- Docker image: `pablodelarco/opennebula` on Docker Hub
- Helm chart: GitHub Pages repository
- CI/CD: Automated builds with Trivy scanning
- Production: Port 4124 (monitoring), port 22 (SSH), stable hostname

**Tech stack:**
- Docker: Ubuntu 24.04, OpenNebula 7.0, supervisord
- Helm: Chart v0.1.0, MariaDB subchart
- CI/CD: GitHub Actions, Trivy, chart-releaser-action
- ~8,933 lines of code

## Requirements

### Validated

- ✓ Docker image uses Ubuntu 24.04 LTS base — v1.1
- ✓ OpenNebula 7.0 packages installed and functional — v1.1
- ✓ Services start without systemd — v1.1
- ✓ Configuration via environment variables — v1.1
- ✓ Services included: oned, Sunstone, FireEdge, OneFlow, OneGate — v1.1
- ✓ GitHub Actions workflow builds Docker image on push/tag — v1.1
- ✓ Scheduled workflow detects new OpenNebula releases — v1.1
- ✓ Images pushed to Docker Hub (pablodelarco/opennebula) — v1.1
- ✓ Trivy vulnerability scanning fails on CRITICAL/HIGH — v1.1
- ✓ Docker image tags align with OpenNebula version — v1.1
- ✓ oned runs as StatefulSet with persistent volume — v1.1
- ✓ MariaDB deployed as subchart dependency — v1.1
- ✓ SSH keys persist across restarts — v1.1
- ✓ Config files managed via ConfigMaps — v1.1
- ✓ Liveness/readiness probes on oned API — v1.1
- ✓ FireEdge accessible via Ingress — v1.1
- ✓ values.yaml allows full customization — v1.1
- ✓ Port 4124 UDP for monitoring — v1.1
- ✓ Port 22 TCP for SSH transfer manager — v1.1
- ✓ VNM transparent proxy configurable — v1.1
- ✓ Explicit hostname configuration — v1.1

### Active

(Next milestone requirements will be defined here)

### Out of Scope

- VMware/ESXi integration — focus on KVM/LXC only
- Paid OpenNebula Enterprise features — community edition only
- Multi-cloud provider integrations — keep scope focused
- Hypervisor node deployment — control plane only; hypervisors external to K8s
- PostgreSQL backend — MariaDB is standard

## Context

**Distribution:**
- Docker image: Docker Hub (pablodelarco/opennebula)
- Helm chart: https://pablodelarco.github.io/opennebula-helm

**Architecture:**
- oned is the central daemon; scheduler/monitoring auto-start with it
- Hypervisors (KVM/LXC) CANNOT run in Kubernetes — control plane only
- supervisord for process management (no systemd in containers)
- MariaDB required for production (SQLite doesn't support concurrent writes)
- SSH key persistence via PV + optional user-provided keys

## Constraints

- **Tech stack**: Helm 3, Docker, GitHub Actions
- **Base image**: Must work with OpenNebula Community Edition (open source)
- **Hypervisors**: KVM/QEMU and LXC only
- **Database**: MariaDB (bundled via subchart or external)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Public project from start | User wants community adoption | ✓ Good |
| MariaDB as subchart | SQLite doesn't support concurrent writes | ✓ Good |
| OpenNebula 7.0 (not 6.10 LTS) | User wants latest version | ✓ Good |
| Control plane only | Hypervisors require hardware virtualization | ✓ Good |
| supervisord over systemd | Containers don't run systemd | ✓ Good |
| OCI registry for MariaDB | Bitnami uses OCI format | ✓ Good |
| Two-job CI pipeline | Clarity: detect-version → build-scan-push | ✓ Good |
| chart-releaser-action | Standard for GitHub Pages Helm repos | ✓ Good |
| StatefulSet FQDN as default hostname | Stable across pod reschedules | ✓ Good |
| Dual-protocol port naming | monitord-tcp/udp for clarity | ✓ Good |

---
*Last updated: 2026-02-03 after v1.1 milestone*

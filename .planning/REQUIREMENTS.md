# Requirements: OpenNebula Helm Chart

**Defined:** 2025-01-23
**Core Value:** A production-ready, self-updating OpenNebula deployment on Kubernetes that the community can use out of the box.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Docker Image

- [x] **IMG-01**: Docker image uses Ubuntu 24.04 LTS as base
- [x] **IMG-02**: OpenNebula 7.0 packages installed and functional
- [x] **IMG-03**: Services start without systemd (manual/entrypoint management)
- [x] **IMG-04**: Configuration via environment variables (DB connection, passwords, etc.)
- [x] **IMG-05**: Services included: oned, Sunstone, FireEdge, OneFlow, OneGate

### CI/CD Pipeline

- [x] **CI-01**: GitHub Actions workflow builds Docker image on push/tag
- [x] **CI-02**: Scheduled workflow detects new OpenNebula releases and triggers builds
- [x] **CI-03**: Images pushed to Docker Hub (pablodelarco/opennebula)
- [x] **CI-04**: Trivy vulnerability scanning fails build on CRITICAL/HIGH vulnerabilities
- [x] **CI-05**: Docker image tags align with OpenNebula version (e.g., 7.0.0, latest)

### Helm Chart

- [ ] **HELM-01**: oned runs as StatefulSet with persistent volume for /var/lib/one
- [ ] **HELM-02**: MariaDB deployed as subchart dependency
- [ ] **HELM-03**: SSH keys stored in Kubernetes secrets, persist across restarts
- [ ] **HELM-04**: OpenNebula config files managed via ConfigMaps
- [ ] **HELM-05**: Liveness probe on oned API, readiness probe on service availability
- [ ] **HELM-06**: FireEdge accessible via Ingress with configurable hostname
- [ ] **HELM-07**: values.yaml allows customization of resources, persistence, ingress

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Advanced Features

- **ADV-01**: VNC console access via Guacamole/noVNC integration
- **ADV-02**: Multi-arch Docker builds (amd64 + arm64)
- **ADV-03**: HA configuration with leader election for oned
- **ADV-04**: OneGate external service exposure for VM contextualization
- **ADV-05**: Prometheus metrics endpoint integration
- **ADV-06**: Backup and restore automation

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| VMware/ESXi integration | Focus on KVM/LXC only per user requirements |
| OpenNebula Enterprise features | Community edition only |
| Hypervisor node deployment | Control plane only; hypervisors must be external to K8s |
| PostgreSQL backend | MariaDB is standard; PostgreSQL is "Technology Preview" |
| Legacy Ruby Sunstone only | FireEdge is the modern UI, include both |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| IMG-01 | Phase 1 | Complete |
| IMG-02 | Phase 1 | Complete |
| IMG-03 | Phase 1 | Complete |
| IMG-04 | Phase 1 | Complete |
| IMG-05 | Phase 1 | Complete |
| CI-01 | Phase 2 | Complete |
| CI-02 | Phase 2 | Complete |
| CI-03 | Phase 2 | Complete |
| CI-04 | Phase 2 | Complete |
| CI-05 | Phase 2 | Complete |
| HELM-01 | Phase 3 | Pending |
| HELM-02 | Phase 3 | Pending |
| HELM-03 | Phase 3 | Pending |
| HELM-04 | Phase 3 | Pending |
| HELM-05 | Phase 3 | Pending |
| HELM-06 | Phase 3 | Pending |
| HELM-07 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 17 total
- Mapped to phases: 17
- Unmapped: 0

---
*Requirements defined: 2025-01-23*
*Last updated: 2026-01-23 - Phase 2 requirements complete*

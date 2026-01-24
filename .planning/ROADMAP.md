# Roadmap: OpenNebula Helm Chart

## Overview

This roadmap delivers a production-ready OpenNebula Helm chart in 3 phases: first build a Docker image with OpenNebula 7.0 and all control plane services (oned, Sunstone, FireEdge, OneFlow, OneGate), then establish CI/CD automation for builds and release detection, and finally create the Helm chart with MariaDB integration, persistent storage, and Kubernetes-native patterns. Each phase produces a complete, verifiable deliverable.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Docker Image** - Build Ubuntu 24.04 image with OpenNebula 7.0 and all services
- [x] **Phase 2: CI/CD Pipeline** - Automated builds, release detection, vulnerability scanning
- [x] **Phase 3: Helm Chart Core** - Complete Kubernetes deployment with MariaDB and ingress

## Phase Details

### Phase 1: Docker Image
**Goal**: Users can pull a working Docker image that runs OpenNebula 7.0 control plane without systemd
**Depends on**: Nothing (first phase)
**Requirements**: IMG-01, IMG-02, IMG-03, IMG-04, IMG-05
**Success Criteria** (what must be TRUE):
  1. User can run the Docker image locally and access oned API via CLI
  2. All services (oned, Sunstone, FireEdge, OneFlow, OneGate) start without errors
  3. Services start via entrypoint without requiring systemd
  4. User can configure database connection and passwords via environment variables
  5. Container uses Ubuntu 24.04 LTS base and OpenNebula 7.0 packages
**Plans**: 2 plans

Plans:
- [x] 01-01-PLAN.md — Create Dockerfile, supervisord config, and entrypoint script
- [x] 01-02-PLAN.md — Build and verify Docker image works

### Phase 2: CI/CD Pipeline
**Goal**: Docker images build automatically on code changes and when new OpenNebula releases are detected
**Depends on**: Phase 1 (needs image to build/push)
**Requirements**: CI-01, CI-02, CI-03, CI-04, CI-05
**Success Criteria** (what must be TRUE):
  1. Pushing code to main branch triggers a new Docker image build
  2. Scheduled workflow detects new OpenNebula releases and triggers rebuild
  3. Images appear on Docker Hub (pablodelarco/opennebula) with correct tags
  4. Builds fail if Trivy finds CRITICAL or HIGH vulnerabilities
  5. Image tags match OpenNebula version (e.g., 7.0.0, latest)
**Plans**: 2 plans

Plans:
- [x] 02-01-PLAN.md — Create GitHub Actions workflow for Docker builds
- [x] 02-02-PLAN.md — Test workflow and verify Docker Hub deployment

### Phase 3: Helm Chart Core
**Goal**: Users can deploy OpenNebula on Kubernetes with a single helm install command
**Depends on**: Phase 1 (deploys the Docker image)
**Requirements**: HELM-01, HELM-02, HELM-03, HELM-04, HELM-05, HELM-06, HELM-07
**Success Criteria** (what must be TRUE):
  1. User can run `helm install` and get a working OpenNebula deployment
  2. oned runs as StatefulSet with persistent storage that survives restarts
  3. MariaDB is deployed automatically as subchart dependency
  4. SSH keys persist across pod restarts via Kubernetes secrets
  5. FireEdge web UI is accessible via Ingress with configurable hostname
**Plans**: 4 plans

Plans:
- [x] 03-01-PLAN.md — Create chart skeleton (Chart.yaml, values.yaml, _helpers.tpl)
- [x] 03-02-PLAN.md — Create core templates (StatefulSet, Service, ConfigMap, Secret)
- [x] 03-03-PLAN.md — Create Ingress, NOTES.txt, and Helm test
- [x] 03-04-PLAN.md — Setup chart publishing (GitHub Actions for chart-releaser)

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Docker Image | 2/2 | ✓ Complete | 2026-01-23 |
| 2. CI/CD Pipeline | 2/2 | ✓ Complete | 2026-01-23 |
| 3. Helm Chart Core | 4/4 | Complete | 2026-01-24 |

---
*Roadmap created: 2025-01-23*
*Last updated: 2026-01-24*

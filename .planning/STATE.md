# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2025-01-23)

**Core value:** A production-ready, self-updating OpenNebula deployment on Kubernetes that the community can use out of the box.
**Current focus:** Phase 4 - Production Hardening - COMPLETE

## Current Position

Phase: 4 of 4 (Production Hardening) - COMPLETE
Plan: 2 of 2 in current phase - COMPLETE
Status: Project complete
Last activity: 2026-02-03 - Completed 04-02-PLAN.md (Hostname & Monitor Address)

Progress: [##########] 100% (10/10 plans complete)

## Performance Metrics

**Velocity:**
- Total plans completed: 10
- Average duration: 8 min
- Total execution time: 76 min

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-docker-image | 2 | 46 min | 23 min |
| 02-cicd-pipeline | 2 | 16 min | 8 min |
| 03-helm-chart-core | 4 | 11 min | 3 min |
| 04-production-hardening | 2 | 3 min | 1.5 min |

**Recent Trend:**
- Last 5 plans: 03-03 (2 min), 03-04 (1 min), 04-01 (1 min), 04-02 (2 min)
- Trend: Production hardening phase very efficient

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: 3-phase structure derived from requirements (Docker Image -> CI/CD -> Helm Chart)
- [Requirements]: OpenNebula 7.0 (not 6.10 LTS) per user preference for latest version
- [01-01]: supervisord for process management (container-native, no systemd)
- [01-01]: RUNLEVEL=1 to prevent service auto-start during apt install
- [01-01]: Auth files created at runtime via entrypoint for security
- [01-02]: sqlite3 to check database bootstrap status before cleanup
- [01-02]: Remove all auth files on fresh bootstrap to avoid conflicts
- [01-02]: Pre-create log files with oneadmin ownership before supervisord starts
- [02-01]: Two-job pipeline (detect-version -> build-scan-push) for clarity
- [02-01]: Trivy with ignore-unfixed: true for actionable vulnerabilities only
- [02-02]: Changed image name to pablodelarco/opennebula (not opennebula-frontend)
- [02-02]: Trivy scanners: 'vuln' to ignore intentional SSH keys
- [03-01]: OCI registry for MariaDB dependency (Bitnami format)
- [03-01]: mariadb.enabled=true by default (simplest quickstart)
- [03-01]: externalDatabase section for production managed databases
- [03-02]: InitContainer with busybox nc for MariaDB wait
- [03-02]: oneuser show 0 for health probes (exec-based)
- [03-02]: lookup function for secret persistence across upgrades
- [03-02]: Headless service for StatefulSet stable network identity
- [03-03]: networking.k8s.io/v1 API for Ingress (modern, not deprecated)
- [03-03]: busybox wget for Helm test with 5s timeout
- [03-04]: chart-releaser-action@v1.7.0 for GitHub Pages publishing
- [03-04]: helm dependency update loop for subchart handling
- [04-01]: Port names monitord-tcp and monitord-udp for dual-protocol clarity
- [04-01]: Ports added to both headless and external services
- [04-02]: Empty hostname default uses StatefulSet FQDN for stable identity
- [04-02]: MONITOR_ADDRESS only set when explicitly configured (preserves auto-detection)
- [04-02]: VNM tproxy section is documentation-focused (hypervisor-side config)

### Pending Todos

None.

### Blockers/Concerns

Production deployment feedback (from colleague):
- ~~Port 4124 UDP missing - monitoring agents can't push metrics~~ RESOLVED in 04-01
- ~~Port 22 missing - SSH transfer manager doesn't work~~ RESOLVED in 04-01
- ~~VNM needs transparent proxy config~~ DOCUMENTED in 04-02 (vnm.tproxy section)
- ~~Hostname issues requiring port forwarding workarounds~~ RESOLVED in 04-02

All production blockers resolved.

## Session Continuity

Last session: 2026-02-03
Stopped at: Completed 04-02-PLAN.md (Hostname & Monitor Address) - PROJECT COMPLETE
Resume file: None - all phases complete

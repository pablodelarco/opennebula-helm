# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2025-01-23)

**Core value:** A production-ready, self-updating OpenNebula deployment on Kubernetes that the community can use out of the box.
**Current focus:** Phase 3 - Helm Chart Core (IN PROGRESS)

## Current Position

Phase: 3 of 3 (Helm Chart Core) - IN PROGRESS
Plan: 2 of 4 in current phase
Status: In progress
Last activity: 2026-01-24 - Completed 03-02-PLAN.md

Progress: [######....] 60%

## Performance Metrics

**Velocity:**
- Total plans completed: 6
- Average duration: 12 min
- Total execution time: 70 min

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-docker-image | 2 | 46 min | 23 min |
| 02-cicd-pipeline | 2 | 16 min | 8 min |
| 03-helm-chart-core | 2 | 8 min | 4 min |

**Recent Trend:**
- Last 5 plans: 02-01 (1 min), 02-02 (15 min), 03-01 (2 min), 03-02 (6 min)
- Trend: Template creation efficient, Helm dependency issues added overhead

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

### Pending Todos

None.

### Blockers/Concerns

None - 03-02 complete, ready for 03-03 (Ingress + optional components).

## Session Continuity

Last session: 2026-01-24
Stopped at: Completed 03-02-PLAN.md
Resume file: None - ready for 03-03-PLAN.md

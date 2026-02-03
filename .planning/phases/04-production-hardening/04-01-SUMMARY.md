---
phase: 04-production-hardening
plan: 01
subsystem: infra
tags: [kubernetes, docker, ports, monitoring, ssh, helm]

# Dependency graph
requires:
  - phase: 03-helm-chart-core
    provides: Base Helm chart with StatefulSet and Service definitions
provides:
  - Port 4124 TCP/UDP exposed for hypervisor monitoring (monitord)
  - Port 22 TCP exposed for SSH transfer manager operations
  - Full port exposure across Dockerfile, Service, and StatefulSet
affects: [production deployments, hypervisor integration]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dual-protocol port exposure (same port number for TCP and UDP)"
    - "Consistent port naming across Service and StatefulSet (monitord-tcp, monitord-udp, ssh)"

key-files:
  created: []
  modified:
    - docker/Dockerfile
    - charts/opennebula/templates/service.yaml
    - charts/opennebula/templates/statefulset.yaml

key-decisions:
  - "Port names monitord-tcp and monitord-udp for clarity with same port number"
  - "Add ports to both headless and external services for full network coverage"

patterns-established:
  - "Port naming: protocol suffix for same-port-different-protocol scenarios"

# Metrics
duration: 1min
completed: 2026-02-03
---

# Phase 04 Plan 01: Port Exposure Summary

**Added monitoring (4124 TCP+UDP) and SSH (22) ports across Dockerfile, Kubernetes Service, and StatefulSet for hypervisor communication**

## Performance

- **Duration:** 1 min
- **Started:** 2026-02-03T12:40:43Z
- **Completed:** 2026-02-03T12:41:52Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- Exposed port 4124 TCP and UDP for monitord (hypervisor monitoring probes)
- Exposed port 22 TCP for SSH transfer manager operations
- Updated both headless and external Kubernetes services
- Documented all ports with inline comments

## Task Commits

Each task was committed atomically:

1. **Task 1: Add port 4124 and 22 to Dockerfile EXPOSE** - `c91ee5d` (feat)
2. **Task 2: Add monitoring and SSH ports to Service** - `fe873b2` (feat)
3. **Task 3: Add monitoring and SSH containerPorts to StatefulSet** - `fe6dd31` (feat)

## Files Created/Modified
- `docker/Dockerfile` - Added EXPOSE 4124 22 with documentation comments
- `charts/opennebula/templates/service.yaml` - Added 3 new ports to both headless and external services
- `charts/opennebula/templates/statefulset.yaml` - Added 3 new containerPort definitions

## Decisions Made
- Used unique port names (monitord-tcp, monitord-udp) since Kubernetes requires unique names even when port numbers are the same with different protocols
- Added ports to both headless and external services to ensure full network coverage for pod DNS resolution and external access

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Port exposure complete, hypervisors can now push monitoring metrics to port 4124
- SSH transfer manager can operate on port 22
- Ready for Phase 04 Plan 02 (if exists) or production testing

---
*Phase: 04-production-hardening*
*Completed: 2026-02-03*

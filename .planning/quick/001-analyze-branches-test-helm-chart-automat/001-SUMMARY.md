---
phase: quick
plan: 001
subsystem: provisioning
tags: [ssh, opennebula, ansible, docker, helm]

# Dependency graph
requires:
  - phase: feature/host-provisioning
    provides: Provisioner job and frontend SSH key sharing
provides:
  - Automatic SSH known_hosts population for provisioned hosts
  - StrictHostKeyChecking=accept-new in frontend SSH config
  - Belt-and-suspenders ssh-keyscan collection in provisioner
affects: [host-provisioning, production-deployment]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SSH config: StrictHostKeyChecking=accept-new for automated deployments"
    - "Belt-and-suspenders: primary mechanism + backup collection"

key-files:
  created: []
  modified:
    - docker/entrypoint.sh
    - docker/provisioner/roles/opennebula-register/tasks/main.yml
    - charts/opennebula/values.yaml

key-decisions:
  - "StrictHostKeyChecking=accept-new as primary solution (safer than 'no', automatic unlike 'yes')"
  - "Added ssh-keyscan as belt-and-suspenders backup for future ConfigMap integration"

patterns-established:
  - "SSH host key handling: accept-new mode for automated provisioning"

# Metrics
duration: 2min
completed: 2026-01-25
---

# Quick Task 001: Automate SSH known_hosts Summary

**SSH known_hosts automation via StrictHostKeyChecking=accept-new config and ssh-keyscan collection**

## Performance

- **Duration:** 2 min
- **Started:** 2026-01-25T21:29:44Z
- **Completed:** 2026-01-25T21:31:09Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- Frontend SSH config with StrictHostKeyChecking=accept-new eliminates manual ssh-keyscan
- Provisioner collects SSH host keys after registration (for optional future use)
- Documentation in values.yaml explains automatic known_hosts behavior

## Task Commits

Each task was committed atomically:

1. **Task 1: Configure SSH StrictHostKeyChecking in Frontend** - `85056fb` (feat)
2. **Task 2: Add Explicit ssh-keyscan in Provisioner** - `4fcebc6` (feat)
3. **Task 3: Document the Solution** - `9be4830` (docs)

## Files Created/Modified
- `docker/entrypoint.sh` - Added SSH config with StrictHostKeyChecking=accept-new
- `docker/provisioner/roles/opennebula-register/tasks/main.yml` - Added ssh-keyscan collection tasks
- `charts/opennebula/values.yaml` - Documented SSH host key handling behavior

## Decisions Made
- **StrictHostKeyChecking=accept-new:** Safer than "no" (still validates known hosts), but automatic for new hosts (unlike "yes"). Standard approach for automated OpenNebula deployments.
- **Belt-and-suspenders approach:** Primary solution is SSH config; provisioner collects keys as backup for potential ConfigMap-based approach in future.

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- SSH known_hosts is now fully automated
- Manual `kubectl exec ... ssh-keyscan` step eliminated
- Hosts should transition to MONITORED state without intervention
- Ready for end-to-end testing with real hypervisors

---
*Phase: quick*
*Completed: 2026-01-25*

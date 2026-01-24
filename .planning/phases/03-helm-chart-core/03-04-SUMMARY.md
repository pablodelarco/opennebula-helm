---
phase: 03-helm-chart-core
plan: 04
subsystem: infra
tags: [helm, github-actions, chart-releaser, ci-cd]

# Dependency graph
requires:
  - phase: 03-03
    provides: Complete chart templates (Ingress, NOTES.txt, Helm test)
provides:
  - GitHub Actions workflow for chart publishing to GitHub Pages
  - Users can helm repo add and helm install
affects: [deployment, documentation, users]

# Tech tracking
tech-stack:
  added:
    - helm/chart-releaser-action@v1.7.0
  patterns:
    - Chart releases via GitHub Pages
    - Automated helm dependency update before release

key-files:
  created:
    - .github/workflows/release-chart.yaml
  modified: []

key-decisions:
  - "chart-releaser-action@v1.7.0 for standard Helm chart publishing"
  - "Trigger on charts/** path changes to main branch"
  - "helm dependency update loop handles subchart dependencies"

patterns-established:
  - "chart-releaser workflow pattern for Helm chart CI/CD"

# Metrics
duration: 1min
completed: 2026-01-24
---

# Phase 3 Plan 04: Chart Publishing Workflow Summary

**GitHub Actions workflow publishes Helm chart to GitHub Pages using chart-releaser-action, enabling users to helm repo add and helm install**

## Performance

- **Duration:** 1 min
- **Started:** 2026-01-24T17:29:23Z
- **Completed:** 2026-01-24T17:30:41Z
- **Tasks:** 2 (1 implementation, 1 validation)
- **Files created:** 1

## Accomplishments

- chart-releaser workflow triggers on charts/ changes to main branch
- Workflow runs helm dependency update to handle MariaDB subchart
- Complete chart passes helm lint --strict and template validation
- Ready for users to `helm repo add` after first chart release

## Task Commits

Each task was committed atomically:

1. **Task 1: Create chart-releaser workflow** - `39063f1` (feat)
2. **Task 2: Validate complete chart** - validation only, no commit

## Files Created/Modified

- `.github/workflows/release-chart.yaml` - Chart publishing workflow using chart-releaser-action@v1.7.0

## Decisions Made

- **chart-releaser-action@v1.7.0:** Standard Helm community tool for GitHub Pages publishing
- **Trigger on charts/** path changes:** Matches docker-build pattern for consistency
- **helm dependency update loop:** Ensures MariaDB subchart is packaged correctly

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - workflow uses GITHUB_TOKEN (automatic for Actions).

After first chart release, users can:
```bash
helm repo add opennebula https://pablodelarco.github.io/opennebula-helm
helm install my-opennebula opennebula/opennebula
```

## Next Phase Readiness

- Phase 3 complete: All 4 plans executed successfully
- Full Helm chart ready for release
- To trigger first release: bump version in Chart.yaml and push to main

---
*Phase: 03-helm-chart-core*
*Completed: 2026-01-24*

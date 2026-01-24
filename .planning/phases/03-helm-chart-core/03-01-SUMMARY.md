---
phase: 03-helm-chart-core
plan: 01
subsystem: helm-chart
tags: [helm, chart, kubernetes, mariadb]
dependency-graph:
  requires: [02-cicd-pipeline]
  provides: [chart-scaffold, values-schema, template-helpers]
  affects: [03-02, 03-03, 03-04]
tech-stack:
  added: [helm-chart-v2, bitnami-mariadb]
  patterns: [conditional-dependency, external-db-support]
key-files:
  created:
    - charts/opennebula/Chart.yaml
    - charts/opennebula/values.yaml
    - charts/opennebula/templates/_helpers.tpl
    - charts/opennebula/.helmignore
  modified: []
decisions:
  - id: helm-01
    choice: "OCI registry for MariaDB dependency"
    reason: "Bitnami charts use OCI format"
  - id: helm-02
    choice: "mariadb.enabled=true by default"
    reason: "Easiest quickstart experience"
  - id: helm-03
    choice: "External database support via externalDatabase section"
    reason: "Production deployments often use managed databases"
metrics:
  duration: 2 min
  tasks: 3/3
  commits: 3
  completed: 2026-01-24
---

# Phase 03 Plan 01: Chart Skeleton Summary

**One-liner:** Helm chart scaffold with Chart.yaml (MariaDB OCI dependency), values.yaml (all HELM-07 config options), and _helpers.tpl (name/label/database helpers).

## What Was Built

### Chart.yaml
- apiVersion v2 application chart
- appVersion 7.0.0 (OpenNebula version)
- MariaDB ~14.0 dependency from OCI registry
- Conditional dependency: `condition: mariadb.enabled`

### values.yaml
Complete configuration schema covering HELM-07 requirements:
- **image:** pablodelarco/opennebula with tag/pullPolicy
- **opennebula:** adminPassword setting
- **mariadb:** Subchart config (enabled by default)
- **externalDatabase:** Host/port/credentials for external DB
- **persistence:** 20Gi for /var/lib/one
- **service:** ClusterIP type
- **ingress:** Disabled by default
- **ssh:** Optional pre-existing keys
- **resources:** Empty (no defaults per CONTEXT.md)
- **nodeSelector/tolerations/affinity:** Standard pod placement

### _helpers.tpl
Template helper functions:
- `opennebula.name` - Chart name (truncated)
- `opennebula.fullname` - Release-qualified name
- `opennebula.chart` - Chart name + version
- `opennebula.labels` - Full Kubernetes labels
- `opennebula.selectorLabels` - Minimal immutable selectors
- `opennebula.mariadb.host` - DB host (subchart or external)
- `opennebula.mariadb.port` - DB port
- `opennebula.mariadb.database` - Database name
- `opennebula.mariadb.username` - DB username
- `opennebula.mariadb.secretName` - Secret containing password

## Task Execution

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create Chart.yaml with MariaDB dependency | 4c8d568 | Chart.yaml, .helmignore |
| 2 | Create values.yaml with all configuration options | 2280cf9 | values.yaml |
| 3 | Create _helpers.tpl with standard template functions | 9017c15 | templates/_helpers.tpl |

## Verification Results

```
$ helm lint charts/opennebula --set mariadb.enabled=false
==> Linting charts/opennebula
[INFO] Chart.yaml: icon is recommended
[WARNING] chart directory is missing these dependencies: mariadb
1 chart(s) linted, 0 chart(s) failed

$ helm dependency list charts/opennebula
NAME     VERSION  REPOSITORY                               STATUS
mariadb  ~14.0    oci://registry-1.docker.io/bitnamicharts missing
```

Lint passes (0 failed). Dependency "missing" is expected - will be fetched during `helm dependency build`.

## Deviations from Plan

None - plan executed exactly as written.

## Decisions Made

| ID | Decision | Rationale |
|----|----------|-----------|
| helm-01 | OCI registry for MariaDB | Bitnami charts use OCI format (oci://registry-1.docker.io/bitnamicharts) |
| helm-02 | mariadb.enabled=true by default | Simplest quickstart - no external DB needed |
| helm-03 | externalDatabase section | Supports production deployments with managed databases |

## Next Plan Readiness

**Ready for 03-02:** StatefulSet + Services
- Chart scaffold complete
- Helper functions available for templates
- Values schema defined for all configuration
- No blockers identified

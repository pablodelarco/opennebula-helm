---
status: complete
phase: 03-helm-chart-core
source: 03-01-SUMMARY.md, 03-02-SUMMARY.md, 03-03-SUMMARY.md, 03-04-SUMMARY.md
started: 2026-01-25T12:40:00Z
updated: 2026-01-25T13:00:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Helm Lint Passes
expected: helm lint ./charts/opennebula shows "0 chart(s) failed"
result: pass

### 2. Helm Install Works
expected: Running `helm list` shows my-opennebula deployed with STATUS: deployed
result: pass

### 3. StatefulSet with Persistence
expected: Run `kubectl get pvc` - shows data-my-opennebula-0 PVC bound
result: pass

### 4. MariaDB Subchart Deployed
expected: Run `kubectl get pods` - shows my-opennebula-mariadb-0 running
result: pass

### 5. NOTES.txt Displays
expected: Run `helm get notes my-opennebula` - shows access instructions
result: pass

### 6. Chart Release Workflow Exists
expected: File .github/workflows/release-chart.yaml exists
result: pass

## Summary

total: 6
passed: 6
issues: 0
pending: 0
skipped: 0

## Gaps

[none]

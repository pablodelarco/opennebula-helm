---
phase: quick
plan: 003
subsystem: helm-ssh
tags: [ssh, keygen, pre-install-hook, rbac, automation]

dependency-graph:
  requires: []
  provides: [ssh-auto-generation, zero-config-ssh]
  affects: []

tech-stack:
  added: []
  patterns: [pre-install-hook, rbac-for-hooks]

key-files:
  created:
    - charts/opennebula/templates/job-ssh-keygen.yaml
  modified:
    - charts/opennebula/values.yaml
    - charts/opennebula/templates/statefulset.yaml
    - charts/opennebula/templates/job-host-provisioner.yaml
    - charts/opennebula/templates/secret-provisioner-ssh.yaml

decisions:
  - id: keygen-job
    choice: Pre-install hook Job with kubectl
    rationale: Generates keys before main resources, creates Kubernetes secret via API

metrics:
  duration: 6 min
  completed: 2026-01-25
---

# Quick Task 003: Auto-Generate SSH Keys Summary

**One-liner:** Pre-install hook Job generates ed25519 SSH key pair, shared between frontend and provisioner for zero-config hypervisor provisioning.

## Objective Achieved

Implemented automatic SSH key generation for the OpenNebula Helm chart, eliminating manual SSH key configuration when using onedeploy.

## What Was Built

### 1. SSH Auto-Generation Option (values.yaml)
Added `ssh.autoGenerate: true` option that enables automatic key generation when onedeploy is enabled and no manual keys are provided.

### 2. Pre-Install Hook Job (job-ssh-keygen.yaml)
Created a Kubernetes Job with:
- **ServiceAccount, Role, RoleBinding** for secret creation RBAC
- **Pre-install hook** (weight: -5) to run before main resources
- **bitnami/kubectl image** for ssh-keygen and kubectl commands
- **Idempotent behavior** - skips if secret already exists

### 3. Unified SSH Secret
Both frontend (StatefulSet) and provisioner (Job) now reference the same `{release}-ssh-generated` secret when auto-generation is active.

## Logic Flow

```
User enables onedeploy.enabled=true
  |
  v
Is ssh.autoGenerate=true? (default: yes)
  |
  +-- YES --> No manual keys? --> Pre-install Job generates keys
  |                              --> Creates secret: {release}-ssh-generated
  |                              --> Frontend and Provisioner use this secret
  |
  +-- NO --> User must provide keys manually
```

## Commits

| # | Hash | Description | Files |
|---|------|-------------|-------|
| 1 | 27bf9ab | Add ssh.autoGenerate option | values.yaml |
| 2 | 25dd69e | Create pre-install hook Job | job-ssh-keygen.yaml |
| 3 | 8146e4f | Add documentation comments | secret-provisioner-ssh.yaml |
| 4 | e3fdbd9 | Update frontend to use generated secret | statefulset.yaml |
| 5 | a6a0452 | Update provisioner to use generated secret | job-host-provisioner.yaml |

## Verification Results

### Helm Lint
```
1 chart(s) linted, 0 chart(s) failed
```

### Auto-Generate Flow (onedeploy.enabled=true, no manual keys)
- SSH-keygen Job rendered: YES (14 component references)
- Secret name used: `{release}-ssh-generated`
- Both frontend and provisioner reference same secret

### Manual Key Flow (onedeploy.provisioner.ssh.privateKey set)
- SSH-keygen Job rendered: NO
- Secret name used: `{release}-provisioner-ssh`
- Both frontend and provisioner reference manual secret

## Deviations from Plan

None - plan executed exactly as written.

## Testing Guidance

To test in a real cluster:

```bash
# Deploy with auto-generated keys
helm install opennebula charts/opennebula \
  --set onedeploy.enabled=true \
  --set 'onedeploy.node.hosts.myhost.ansible_host=192.168.1.100'

# Verify pre-install hook ran
kubectl get jobs | grep ssh-keygen

# Verify secret was created
kubectl get secret opennebula-ssh-generated

# Verify frontend mounts the secret
kubectl describe pod opennebula-0 | grep ssh
```

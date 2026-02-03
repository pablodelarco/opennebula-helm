---
phase: quick
plan: 002
subsystem: testing
tags: [helm, testing, docker, architecture, ssh]

# Dependency graph
requires:
  - phase: quick-001
    provides: SSH StrictHostKeyChecking automation
provides:
  - Helm chart validation
  - Docker image architecture analysis
  - End-to-end deployment test
affects: [helm-chart, provisioner, documentation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Two-image architecture: frontend (1GB) + provisioner (116MB)"
    - "Helm post-install hooks for one-time setup"
    - "SSH key sharing between frontend and provisioner"

key-files:
  created: []
  modified: []
  tested:
    - charts/opennebula/
    - docker/Dockerfile
    - docker/provisioner/Dockerfile

key-decisions:
  - "Keep two Docker images (separation of concerns, security, efficiency)"
  - "SSH keys must be provided in values.yaml OR use existingSecret"
  - "Future: auto-generate SSH keys in pre-install hook"

patterns-established:
  - "Provisioner uses root SSH access with user-provided keys"
  - "Frontend SSH config accepts new host keys automatically"

# Metrics
duration: 45min
completed: 2026-01-25
---

# Quick Task 002: Test Helm Chart and Analyze Docker Architecture

## Performance

- **Duration:** ~45 min (including debugging)
- **Started:** 2026-01-25T22:35:00Z
- **Completed:** 2026-01-25T23:25:00Z

## Test Results

| Component | Status | Notes |
|-----------|--------|-------|
| Helm lint | ✅ Pass | Chart valid |
| Helm install | ✅ Pass | All pods running |
| MariaDB | ✅ Running | StatefulSet healthy |
| OpenNebula frontend | ✅ Running | 2/2 containers (main + nginx proxy) |
| Provisioner Job | ✅ Completed | Host registered successfully |
| Host 192.168.1.57 | ✅ Online | Monitoring working |
| Virtual Network | ✅ Ready | Bridge br0 configured |
| Datastores | ✅ Online | system, default, files |
| SSH known_hosts | ✅ Auto-populated | StrictHostKeyChecking accept-new working |

## Architecture Analysis: Why Two Docker Images?

### Current Architecture

| Image | Base | Size | Purpose | Lifecycle |
|-------|------|------|---------|-----------|
| opennebula | Ubuntu 24.04 | ~1GB | Frontend (oned, FireEdge, OneFlow, OneGate) | Long-running StatefulSet |
| opennebula-provisioner | Alpine 3.20 | ~116MB | Ansible-based host provisioning | Short-lived Job |

### Reasons to Keep Separate

1. **Different Lifecycles**
   - Frontend: Continuous StatefulSet
   - Provisioner: One-time Job at helm install, then exits

2. **Security (Attack Surface)**
   - Frontend: Only OpenNebula daemons
   - Provisioner: Ansible, SSH keys, root credentials to hypervisors
   - Separation prevents long-running pod from having hypervisor root access

3. **Resource Efficiency**
   - Provisioner: 100m CPU, 128Mi RAM, runs ~2 min
   - Why carry Ansible overhead in perpetuity?

4. **Update Flexibility**
   - Can update provisioner independently
   - Different release cycles

### Recommendation

**Keep them separate.** This follows Kubernetes best practices for single-responsibility and security isolation.

## Issues Discovered

1. **SSH key format confusion**: Template expects raw key, not base64 encoded
   - Values documentation should clarify

2. **ansible_user mismatch**: If using `root`, the SSH key must be in root's authorized_keys
   - Documentation should emphasize this

## Future Improvement: Auto-Generate SSH Keys

User requested automatic SSH key generation. Proposed approach:

```yaml
# Pre-install hook job that:
# 1. Generates SSH key pair
# 2. Creates Secret with keys
# 3. Both frontend and provisioner mount that Secret

# No manual SSH key configuration needed
onedeploy:
  enabled: true
  ssh:
    autoGenerate: true  # NEW: auto-generate keys in pre-install hook
```

This would require:
1. New pre-install hook Job (`job-ssh-keygen.yaml`)
2. Modified secret template to support auto-generation
3. InitContainer or entrypoint logic to wait for secret

## Next Steps

- [ ] Implement SSH key auto-generation (new quick task)
- [ ] Update documentation for values.yaml SSH section
- [ ] Consider merging to main branch

---
*Phase: quick*
*Completed: 2026-01-25*

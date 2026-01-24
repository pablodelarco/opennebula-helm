# Phase 3: Helm Chart Core - Context

**Discussed:** 2026-01-23
**Phase Goal:** Users can deploy OpenNebula on Kubernetes with a single helm install command

## Critical Constraint

**PoC Requirements** (non-negotiable):
- Single Helm chart (umbrella with subcharts OK)
- All images/charts in public registries — NO imagePullSecrets
- Must work immediately with just:
  ```
  helm repo add <repository>
  helm install <release_name> <chart>
  ```

## Decisions

### Database Integration

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Database deployment | Bitnami MariaDB subchart | Standard Helm practice, matches HELM-02 requirement |
| Credentials handling | Auto-generate by default, allow override | Flexibility for both PoC and production |
| External DB support | Not in v1 | Keep scope focused on working out-of-box |

**Implementation notes:**
- Use `bitnami/mariadb` as Chart.yaml dependency
- Generate random password if not provided in values
- Store credentials in Kubernetes secret

### Secrets & Credentials

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Admin password | Default `opennebula`, overridable | Easy PoC testing, production can override |
| SSH keys | Dual-mode (Docker + K8s compatible) | Works standalone and in cluster |

**SSH key implementation:**
- Docker standalone: Entrypoint generates keys if not present (current behavior)
- Kubernetes: Helm creates secret with SSH keypair, mounts into container
- Entrypoint detects mounted keys and skips generation

### Ingress & Networking

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Default service type | ClusterIP | Standard, works everywhere |
| Ingress | Disabled by default | Not all clusters have ingress controller |
| TLS | Not in v1 | HTTP only for PoC simplicity |

**Service exposure:**
- FireEdge (web UI): Port 2616
- oned API: Port 2633
- OneFlow: Port 2474
- OneGate: Port 5030

### Values Design

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Resource limits | No defaults | Flexible for different environments |
| Storage size | 20Gi default | Good headroom for production use |
| Image tag | `latest` by default | Always get newest version |

## Chart Structure

```
charts/opennebula/
├── Chart.yaml           # With mariadb dependency
├── values.yaml          # All configurable values
├── templates/
│   ├── _helpers.tpl     # Template helpers
│   ├── statefulset.yaml # oned StatefulSet
│   ├── service.yaml     # ClusterIP services
│   ├── configmap.yaml   # OpenNebula config files
│   ├── secret.yaml      # Credentials and SSH keys
│   ├── ingress.yaml     # Optional ingress
│   └── pvc.yaml         # Persistent volume claim
└── charts/              # Subcharts (mariadb)
```

## Values.yaml Structure

```yaml
# Image
image:
  repository: pablodelarco/opennebula
  tag: latest
  pullPolicy: IfNotPresent

# OpenNebula settings
opennebula:
  adminPassword: opennebula  # Default, should override in production

# Database
mariadb:
  enabled: true
  auth:
    database: opennebula
    username: oneadmin
    # password auto-generated if not set

# Persistence
persistence:
  enabled: true
  size: 20Gi
  # storageClass: ""  # Use default

# Services
service:
  type: ClusterIP

# Ingress
ingress:
  enabled: false
  # hostname: opennebula.example.com
  # annotations: {}

# Resources (no defaults)
resources: {}
```

## Deferred Ideas

Captured for future phases:

- External MariaDB support (v2)
- TLS/cert-manager integration (v2)
- Multi-architecture images (v2)
- HA configuration (v2)

## Next Steps

Ready for research and planning:
- `/gsd:plan-phase 3` — create execution plans

---
*Context created: 2026-01-23*

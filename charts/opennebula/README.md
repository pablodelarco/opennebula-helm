# OpenNebula Helm Chart

Deploy OpenNebula on Kubernetes with a single command.

[![Helm](https://img.shields.io/badge/Helm-3.x-blue)](https://helm.sh)
[![OpenNebula](https://img.shields.io/badge/OpenNebula-7.0-green)](https://opennebula.io)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

## Features

- **One-command deployment** - `helm install` gets you a working OpenNebula
- **MariaDB included** - Production-ready database as subchart
- **Persistent storage** - Data survives pod restarts
- **Ingress support** - Optional external access configuration
- **Auto-updating image** - CI/CD detects new OpenNebula releases

## Quick Start

```bash
# Add the repo
helm repo add opennebula https://pablodelarco.github.io/opennebula-helm
helm repo update

# Install
helm install opennebula opennebula/opennebula

# Or install with custom values
helm install opennebula opennebula/opennebula -f values.yaml

# Access the UI
kubectl port-forward svc/opennebula 8080:2616
# Open http://localhost:8080/fireedge/sunstone
# Login: oneadmin / <generated-password>
```

Get the admin password:
```bash
kubectl get secret opennebula-credentials -o jsonpath='{.data.oneadmin-password}' | base64 -d
```

## Configuration

Modify [values.yaml](values.yaml):

```yaml
## Image configuration
image:
  repository: pablodelarco/opennebula
  tag: "latest"
  pullPolicy: IfNotPresent

## OpenNebula settings
opennebula:
  adminPassword: "your-secure-password"

## MariaDB subchart configuration
mariadb:
  enabled: true
  auth:
    database: opennebula
    username: oneadmin
  primary:
    persistence:
      enabled: true
      size: 8Gi

## External database (when mariadb.enabled=false)
externalDatabase:
  host: ""
  port: 3306
  database: opennebula
  username: oneadmin
  password: ""

## Persistence for OpenNebula data
persistence:
  enabled: true
  size: 20Gi
  accessMode: ReadWriteOnce

## Service configuration
service:
  type: ClusterIP

## Ingress configuration
ingress:
  enabled: false
  className: ""
  hostname: opennebula.local
  tls:
    enabled: false
    secretName: ""

## Resource limits
resources: {}
  # limits:
  #   cpu: 2
  #   memory: 4Gi
  # requests:
  #   cpu: 500m
  #   memory: 1Gi

## Node placement
nodeSelector: {}
tolerations: []
affinity: {}
```

Install with custom values:
```bash
helm install opennebula opennebula/opennebula -f values.yaml
```

### Common Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | OpenNebula image | `pablodelarco/opennebula` |
| `image.tag` | Image tag | `7.0.0` |
| `opennebula.adminPassword` | oneadmin password | Auto-generated |
| `mariadb.enabled` | Deploy MariaDB subchart | `true` |
| `ingress.enabled` | Enable ingress | `false` |
| `ingress.hostname` | Ingress hostname | `opennebula.local` |
| `persistence.size` | PVC size | `10Gi` |

See [values.yaml](values.yaml) for all options.

## Architecture

```
┌─────────────────────────────────────────┐
│          Kubernetes Cluster             │
│  ┌─────────────┐    ┌─────────────┐    │
│  │  OpenNebula │    │   MariaDB   │    │
│  │ StatefulSet │    │ StatefulSet │    │
│  │             │    │             │    │
│  │ - oned      │◄───┤             │    │
│  │ - Sunstone  │    │             │    │
│  │ - FireEdge  │    │             │    │
│  │ - Scheduler │    │             │    │
│  └─────────────┘    └─────────────┘    │
└─────────────────────────────────────────┘
```

## Adding Hypervisor Hosts

After installation, add KVM/LXC hosts manually:

```bash
# SSH into the pod
kubectl exec -it opennebula-0 -c opennebula -- bash

# Add a host
onehost create <hostname> -i kvm -v kvm
```

Or use the `feature/host-provisioning` branch for automatic host provisioning.

## Troubleshooting

**Pods not starting:**
```bash
kubectl describe pod opennebula-0
kubectl logs opennebula-0 -c opennebula
```

**Database connection issues:**
```bash
kubectl logs opennebula-mariadb-0
```

**Check OpenNebula services:**
```bash
kubectl exec opennebula-0 -c opennebula -- supervisorctl status
```

## Contributing

Issues and PRs welcome at [github.com/pablodelarco/opennebula-helm](https://github.com/pablodelarco/opennebula-helm)

## License

Apache 2.0

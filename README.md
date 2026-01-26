# OpenNebula Helm Chart

A production-ready Helm chart for deploying OpenNebula on Kubernetes.

[![Helm](https://img.shields.io/badge/Helm-3.x-blue)](https://helm.sh)
[![OpenNebula](https://img.shields.io/badge/OpenNebula-7.0-green)](https://opennebula.io)
[![Docker](https://img.shields.io/docker/pulls/pablodelarco/opennebula)](https://hub.docker.com/r/pablodelarco/opennebula)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

## Why This Chart?

OpenNebula is powerful but complex to deploy. This chart solves the hard problems:

- **No systemd in containers** — OpenNebula expects systemd, but containers don't have it. We use supervisord to manage all services cleanly.
- **Database included** — MariaDB deployed automatically as a subchart.
- **Persistent storage** — Data survives pod restarts and upgrades.
- **Auto-updating** — CI/CD pipeline detects new OpenNebula releases and builds fresh images.

## Features

### One-Command Deployment
```bash
helm install opennebula opennebula/opennebula
```
Deploys the complete OpenNebula control plane: oned, Sunstone, FireEdge, Scheduler, and MariaDB.

### Production Ready
- StatefulSet for stable network identity
- Persistent volumes for data durability
- Secrets management for credentials
- Health checks and readiness probes

### Flexible Configuration
- Ingress support for external access
- External database option for managed services
- Customizable resource limits
- Multiple storage class support

## Installation

### Quick Start

```bash
# Add the Helm repository
helm repo add opennebula https://pablodelarco.github.io/opennebula-helm
helm repo update

# Install with defaults
helm install opennebula opennebula/opennebula

# Or install with custom values
helm install opennebula opennebula/opennebula -f values.yaml

# Access the UI
kubectl port-forward svc/opennebula 8080:2616
```

Open http://localhost:8080/fireedge/sunstone

**Remote access via SSH tunnel:**

If you're connecting to the cluster via SSH, set up a tunnel to access the UI from your local machine:

```bash
# On the cluster node - start port-forward bound to all interfaces
kubectl port-forward svc/opennebula 8080:2616 --address 0.0.0.0 &

# On your local machine - create SSH tunnel
ssh -L 8080:localhost:8080 user@cluster-node

# Open in your browser
# http://localhost:8080/fireedge/sunstone
```

Get the admin password:
```bash
kubectl get secret opennebula-credentials -o jsonpath='{.data.oneadmin-password}' | base64 -d
```

### Custom Configuration

Modify your [values.yaml](charts/opennebula/values.yaml):

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

Install:
```bash
helm install opennebula opennebula/opennebula -f values.yaml
```

See [charts/opennebula/values.yaml](charts/opennebula/values.yaml) for all options.

## Architecture

```
┌─────────────────────────────────────────────────┐
│              Kubernetes Cluster                  │
│                                                  │
│  ┌─────────────────┐       ┌──────────────┐     │
│  │   OpenNebula    │       │   MariaDB    │     │
│  │   StatefulSet   │       │  StatefulSet │     │
│  │                 │       │              │     │
│  │  ┌───────────┐  │       │              │     │
│  │  │   oned    │◄─┼───────┤              │     │
│  │  ├───────────┤  │       │              │     │
│  │  │ Scheduler │  │       │              │     │
│  │  ├───────────┤  │       │              │     │
│  │  │ Sunstone  │  │       │              │     │
│  │  ├───────────┤  │       │              │     │
│  │  │ FireEdge  │  │       │              │     │
│  │  └───────────┘  │       └──────────────┘     │
│  └─────────────────┘                            │
│                                                  │
└─────────────────────────────────────────────────┘
```

## Adding Hypervisor Hosts

After installation, add KVM/LXC hosts manually:

```bash
# Copy SSH key to hypervisor
kubectl exec opennebula-0 -c opennebula -- cat /var/lib/one/.ssh/id_rsa.pub
# Add this key to the hypervisor's oneadmin user

# Add the host
kubectl exec opennebula-0 -c opennebula -- onehost create <hostname> -i kvm -v kvm
```

For **automatic host provisioning**, see the [`feature/host-provisioning`](https://github.com/pablodelarco/opennebula-helm/tree/feature/host-provisioning) branch.

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod opennebula-0
kubectl logs opennebula-0 -c opennebula
```

### Database connection issues
```bash
kubectl logs opennebula-mariadb-0
```

### Check services
```bash
kubectl exec opennebula-0 -c opennebula -- supervisorctl status
```

### View oned logs
```bash
kubectl exec opennebula-0 -c opennebula -- cat /var/log/one/oned.log
```

## Contributing

Issues and pull requests welcome at [github.com/pablodelarco/opennebula-helm](https://github.com/pablodelarco/opennebula-helm)

## License

Apache 2.0 — See [LICENSE](LICENSE) for details.

---

**Note:** This is a community project, not officially affiliated with OpenNebula Systems.

# OpenNebula Helm Chart

Deploy OpenNebula on Kubernetes with automatic hypervisor provisioning.

[![Helm](https://img.shields.io/badge/Helm-3.x-blue)](https://helm.sh)
[![OpenNebula](https://img.shields.io/badge/OpenNebula-7.0-green)](https://opennebula.io)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

## Features

- **One-command deployment** - `helm install` gets you a working OpenNebula
- **Automatic host provisioning** - Configure KVM/LXC hypervisors via Ansible
- **Auto-generated SSH keys** - No manual key management required
- **MariaDB included** - Production-ready database as subchart
- **Fast installation** - Core ready in ~2 minutes, hosts provisioned in background

## Quick Start

```bash
# Add the repo
helm repo add opennebula https://pablodelarco.github.io/opennebula-helm
helm repo update

# Install with default settings
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

## Host Provisioning

Add the `onedeploy` section to enable automatic hypervisor provisioning:

```yaml
onedeploy:
  enabled: true

  bootstrap:
    password: "your-ssh-password"  # Used once to inject generated keys

  vars:
    ansible_user: root
    one_version: "7.0"
    vn:
      default:
        managed: true
        template:
          VN_MAD: bridge
          BRIDGE: br0
          AR:
            TYPE: IP4
            IP: 192.168.1.200
            SIZE: 50

  node:
    hosts:
      worker1:
        ansible_host: 192.168.1.10
      worker2:
        ansible_host: 192.168.1.11
```

Install:
```bash
helm install opennebula opennebula/opennebula -f values.yaml
```

Monitor provisioner progress:
```bash
kubectl logs -f job/opennebula-host-provisioner
```

See [values.yaml](values.yaml) for all options.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │  OpenNebula │  │   MariaDB   │  │   Provisioner   │  │
│  │ StatefulSet │  │ StatefulSet │  │      Job        │  │
│  │             │  │             │  │                 │  │
│  │ - oned      │  │             │  │ - Ansible       │  │
│  │ - Sunstone  │◄─┤             │  │ - Host setup    │  │
│  │ - FireEdge  │  │             │  │ - Registration  │  │
│  │ - Scheduler │  │             │  │                 │  │
│  └──────┬──────┘  └─────────────┘  └────────┬────────┘  │
│         │                                    │           │
└─────────┼────────────────────────────────────┼───────────┘
          │              SSH                   │
          ▼                                    ▼
    ┌───────────┐                       ┌───────────┐
    │  KVM/LXC  │                       │  KVM/LXC  │
    │   Host    │                       │   Host    │
    └───────────┘                       └───────────┘
```

## Troubleshooting

**Pods not starting:**
```bash
kubectl describe pod opennebula-0
kubectl logs opennebula-0 -c opennebula
```

**Host provisioning failed:**
```bash
kubectl logs job/opennebula-host-provisioner
```

**Check OpenNebula status:**
```bash
kubectl exec opennebula-0 -c opennebula -- onehost list
kubectl exec opennebula-0 -c opennebula -- onevnet list
```

## Contributing

Issues and PRs welcome at [github.com/pablodelarco/opennebula-helm](https://github.com/pablodelarco/opennebula-helm)

## License

Apache 2.0

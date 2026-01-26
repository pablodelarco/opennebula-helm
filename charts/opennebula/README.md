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

# Access the UI
kubectl port-forward svc/opennebula 8080:2616
# Open http://localhost:8080/fireedge/sunstone
# Login: oneadmin / <generated-password>
```

Get the admin password:
```bash
kubectl get secret opennebula-credentials -o jsonpath='{.data.oneadmin-password}' | base64 -d
```

## Installation with Host Provisioning

Create a `values.yaml`:

```yaml
opennebula:
  adminPassword: "your-secure-password"

onedeploy:
  enabled: true

  # Your SSH password to bootstrap hosts (used once to inject generated keys)
  bootstrap:
    password: "your-ssh-password"

  vars:
    ansible_user: root
    one_version: "7.0"

    # Virtual network configuration
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

  # Hypervisor nodes to provision
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

Or use the install script for progress output:
```bash
./scripts/install.sh opennebula values.yaml
```

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | OpenNebula image | `pablodelarco/opennebula` |
| `image.tag` | Image tag | `7.0.0` |
| `opennebula.adminPassword` | oneadmin password | Auto-generated |
| `mariadb.enabled` | Deploy MariaDB subchart | `true` |
| `onedeploy.enabled` | Enable host provisioning | `false` |
| `onedeploy.bootstrap.password` | SSH password for key injection | `""` |
| `ingress.enabled` | Enable ingress | `false` |
| `persistence.size` | PVC size | `10Gi` |

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

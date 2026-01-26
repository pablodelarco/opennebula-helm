# OpenNebula Helm Chart

A production-ready Helm chart for deploying OpenNebula on Kubernetes, with automatic hypervisor provisioning via Ansible.

[![Helm](https://img.shields.io/badge/Helm-3.x-blue)](https://helm.sh)
[![OpenNebula](https://img.shields.io/badge/OpenNebula-7.0-green)](https://opennebula.io)
[![Docker](https://img.shields.io/docker/pulls/pablodelarco/opennebula)](https://hub.docker.com/r/pablodelarco/opennebula)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

## Why This Chart?

OpenNebula is powerful but complex to deploy. This chart solves the hard problems:

- **No systemd in containers** — OpenNebula expects systemd, but containers don't have it. We use supervisord to manage all services cleanly.
- **Automatic host provisioning** — Manually configuring KVM/LXC hypervisors is tedious. The built-in Ansible provisioner does it for you.
- **SSH key management** — Keys are auto-generated and distributed to hypervisors without manual intervention.
- **Fast iteration** — Core installation in ~2 minutes. Hosts provision in the background while you explore the UI.

## Features

### One-Command Deployment
```bash
helm install opennebula opennebula/opennebula
```
Deploys the complete OpenNebula control plane: oned, Sunstone, FireEdge, Scheduler, and MariaDB.

### Automatic Host Provisioning
Define your hypervisors in `values.yaml` and the chart:
- Installs OpenNebula node packages via Ansible
- Configures libvirt for KVM virtualization
- Registers hosts with the OpenNebula frontend
- Creates virtual networks automatically

### Auto-Generated SSH Keys
No need to manually create or distribute SSH keys:
- Pre-install hook generates a keypair
- Bootstrap job injects the public key into hypervisors (using your existing SSH access)
- Frontend and provisioner share the keys automatically

### Non-Blocking Installation
The provisioner runs in the background:
- UI accessible in ~2 minutes
- Hosts appear as provisioning completes
- No waiting for Ansible to finish

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
```

Get the admin password:
```bash
kubectl get secret opennebula-credentials -o jsonpath='{.data.oneadmin-password}' | base64 -d
```

### Accessing the UI

**Option 1: Direct access (on the cluster node)**
```bash
kubectl port-forward svc/opennebula 8080:2616
# Open http://localhost:8080/fireedge/sunstone
```

**Option 2: Remote access via SSH tunnel**

If you're connecting to the cluster via SSH, set up a tunnel to access the UI from your local machine:

```bash
# On the cluster node - start port-forward bound to all interfaces
kubectl port-forward svc/opennebula 8080:2616 --address 0.0.0.0 &

# On your local machine - create SSH tunnel
ssh -L 8080:localhost:8080 user@cluster-node

# Open in your browser
# http://localhost:8080/fireedge/sunstone
```

Or combine in one command from your local machine:
```bash
ssh -L 8080:localhost:8080 user@cluster-node "kubectl port-forward svc/opennebula 8080:2616"
```

### Configuration

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

### With Host Provisioning

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
      kvm-host-1:
        ansible_host: 192.168.1.10
      kvm-host-2:
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

See [charts/opennebula/values.yaml](charts/opennebula/values.yaml) for all options.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                        │
│                                                               │
│  ┌─────────────────┐  ┌──────────┐  ┌─────────────────────┐  │
│  │   OpenNebula    │  │ MariaDB  │  │    Provisioner      │  │
│  │   StatefulSet   │  │          │  │       Job           │  │
│  │                 │  │          │  │                     │  │
│  │  ┌───────────┐  │  │          │  │  ┌───────────────┐  │  │
│  │  │   oned    │◄─┼──┤          │  │  │    Ansible    │  │  │
│  │  ├───────────┤  │  │          │  │  │               │  │  │
│  │  │ Scheduler │  │  │          │  │  │ - Install ONE │  │  │
│  │  ├───────────┤  │  │          │  │  │ - Setup KVM   │  │  │
│  │  │ Sunstone  │  │  │          │  │  │ - Register    │  │  │
│  │  ├───────────┤  │  │          │  │  └───────┬───────┘  │  │
│  │  │ FireEdge  │  │  └──────────┘  │          │          │  │
│  │  └─────┬─────┘  │                └──────────┼──────────┘  │
│  └────────┼────────┘                           │              │
│           │                                    │              │
└───────────┼────────────────────────────────────┼──────────────┘
            │                                    │
            │              SSH                   │
            ▼                                    ▼
      ┌───────────┐                       ┌───────────┐
      │  KVM/LXC  │                       │  KVM/LXC  │
      │   Host    │                       │   Host    │
      │           │                       │           │
      │  libvirt  │                       │  libvirt  │
      └───────────┘                       └───────────┘
```

## How It Works

### Installation Flow

1. **Pre-install hooks** — Generate SSH keypair, optionally inject into hypervisors
2. **Main deployment** — StatefulSet (OpenNebula), MariaDB, ConfigMaps, Secrets
3. **Background provisioner** — Ansible configures hypervisors while you use the UI

### SSH Key Bootstrap

When `onedeploy.bootstrap.password` is set:
1. SSH keygen job creates a new keypair
2. Bootstrap job uses your password to SSH into each hypervisor
3. Adds the generated public key to `~/.ssh/authorized_keys`
4. Future connections use key-based auth (password no longer needed)

### Provisioner Workflow

The provisioner Job:
1. Waits for OpenNebula API to be ready
2. Runs Ansible playbooks on each host
3. Installs `opennebula-node` packages
4. Configures libvirt and KVM
5. Registers hosts via OpenNebula API
6. Creates virtual networks

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod opennebula-0
kubectl logs opennebula-0 -c opennebula
```

### Provisioner failing
```bash
kubectl logs job/opennebula-host-provisioner
```

### Host not registering
```bash
# Check from inside the pod
kubectl exec opennebula-0 -c opennebula -- onehost list
kubectl exec opennebula-0 -c opennebula -- onehost show 0
```

### SSH connectivity issues
```bash
# Test SSH from the pod
kubectl exec opennebula-0 -c opennebula -- ssh root@<host-ip> hostname
```

## Contributing

Issues and pull requests welcome at [github.com/pablodelarco/opennebula-helm](https://github.com/pablodelarco/opennebula-helm)

## License

Apache 2.0 — See [LICENSE](LICENSE) for details.

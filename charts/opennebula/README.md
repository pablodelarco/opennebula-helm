# OpenNebula

A Helm chart for an **OpenNebula front-end** on Kubernetes.

> **Community-maintained. Not an official OpenNebula Systems product.**
> Maintained by the community on a best-effort basis, without OpenNebula
> Systems support. See [docs.opennebula.io](https://docs.opennebula.io) for
> supported deployment methods.

## TL;DR

```bash
helm repo add opennebula https://pablodelarco.github.io/opennebula-helm
helm install opennebula opennebula/opennebula
```

No database, no secrets and no values file are required. The chart is
self-contained: OpenNebula runs on **SQLite**, exactly like a stock front-end,
with its state on a persistent volume.

## What gets deployed

A single StatefulSet running the OpenNebula control plane:

| Service | Port | Purpose |
|---|---|---|
| `oned` + `one_sched` | 2633 | Core daemon and scheduler |
| FireEdge | 2616 | Web UI |
| OneFlow | 2474 | Service orchestration |
| OneGate | 5030 | VM contextualization gateway |
| OneForm | 13013 | Host provisioning (`oneprovision`, `oneprovider`) |
| OneKS | 10780 | Kubernetes clusters on provisioned hosts |
| Monitord | 4124 | Receives monitoring from hypervisors |

**This is a front-end only.** The image has no `libvirt` and no `qemu`, and no
host is registered at startup, so virtual machines cannot run inside the
container. They run on external hypervisor nodes you attach to it.

## Architecture

```
┌──────────────────── Kubernetes Cluster ────────────────────┐
│                                                            │
│   ┌──────────────────────────────────────┐                 │
│   │   OpenNebula StatefulSet             │                 │
│   │                                      │                 │
│   │   oned  one_sched  FireEdge          │   ┌──────────┐  │
│   │   OneFlow  OneGate                   │◄──┤ PVC 20Gi │  │
│   │   OneForm  OneKS  Monitord           │   │ SQLite   │  │
│   └───────────────┬──────────────────────┘   └──────────┘  │
│                   │                                        │
│      Service (ClientIP)   Service (headless)               │
│      UI and APIs          stable DNS for hypervisors       │
└───────────────────┼────────────────────────────────────────┘
                    │  SSH :22, monitoring :4124
              ┌─────┴──────┐
              │ Hypervisors│  (external, KVM)
              └────────────┘
```

The **headless** Service is what gives the pod a permanent DNS name. That name
is advertised to hypervisor nodes, so they keep finding the front-end after a
restart even though the pod IP changes.

## Configuration

| Value | Default | Description |
|---|---|---|
| `image.repository` | `opennebula/opennebula` | Image repository |
| `image.tag` | `""` | Defaults to the chart's `appVersion` |
| `opennebula.adminPassword` | `opennebula` | Password for `oneadmin` and `serveradmin` |
| `opennebula.hostname` | `""` | Address advertised to hypervisors. Defaults to the StatefulSet FQDN |
| `opennebula.monitorAddress` | `""` | Where hypervisors send monitoring data |
| `persistence.enabled` | `true` | Persist `/var/lib/one` |
| `persistence.size` | `20Gi` | Volume size |
| `persistence.storageClass` | cluster default | Storage class for the volume |
| `resources.requests` | `250m` / `1Gi` | Measured idle usage is ~500 MiB and ~15m CPU |
| `resources.limits` | `2` / `2Gi` | Raise for larger infrastructures |
| `service.type` | `ClusterIP` | Service type |
| `ingress.enabled` | `false` | Expose FireEdge through an Ingress |
| `nodeSelector`, `tolerations`, `affinity` | `{}` | Standard scheduling controls |

Container environment variables, including `DB_BACKEND` for an external MySQL
and `AUTO_UPDATE_ADDONS`, are documented in the
[image README](https://github.com/pablodelarco/opennebula-helm/blob/main/docker/README.md).

## Accessing the UI

```bash
kubectl port-forward svc/opennebula 8080:2616
```

Open http://localhost:8080/fireedge and log in as `oneadmin`.

## Adding hypervisor hosts

Manually:

```bash
kubectl exec opennebula-0 -c opennebula -- cat /var/lib/one/.ssh/id_rsa.pub
# install that key for oneadmin on the hypervisor, then:
kubectl exec opennebula-0 -c opennebula -- onehost create <ip> -i kvm -v kvm
```

Or with **OneForm**, which ships in the image:

```bash
kubectl exec opennebula-0 -c opennebula -- oneprovision create provision.yml
```

Full steps are in the
[repository README](https://github.com/pablodelarco/opennebula-helm#adding-hypervisor-hosts).

## Troubleshooting

Every service logs to the container's stdout, so this is normally enough:

```bash
kubectl logs opennebula-0 -c opennebula
```

`oned`'s own log is included, so start-up failures state their cause directly
without needing a shell inside the pod.

Check the six services are up:

```bash
kubectl exec opennebula-0 -c opennebula -- supervisorctl status
```

## Contributing

Issues and PRs welcome at
[github.com/pablodelarco/opennebula-helm](https://github.com/pablodelarco/opennebula-helm).

## License

Apache 2.0

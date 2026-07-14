# OpenNebula Front-End Community Edition

[OpenNebula](https://opennebula.io) is an open-source cloud and edge computing platform for managing virtualized infrastructure, containers, and multi-cloud deployments.

**Latest Version:** __ONE_VERSION__ (Community Edition)

**Base Image:** Ubuntu 24.04 LTS | **Architecture:** linux/amd64

## Included Components

| Component | Description |
|-----------|-------------|
| opennebula | Core server and scheduler |
| opennebula-fireedge | Modern web UI (FireEdge) |
| opennebula-flow | Multi-VM application orchestration |
| opennebula-gate | VM contextualization gateway |
| opennebula-tools | CLI management tools |

## Exposed Ports

| Port | Service |
|------|---------|
| 22 | SSH |
| 2474 | OneFlow |
| 2616 | FireEdge web UI |
| 2633 | oned XML-RPC API |
| 4124 | Monitord (TCP/UDP) |
| 5030 | OneGate |

## Tags

- `X.Y.Z` (e.g. `__ONE_VERSION__`): immutable-content builds of a specific OpenNebula release. The image is verified at build time to contain exactly the OpenNebula version it is tagged as.
- `latest`: the newest **stable** OpenNebula release. Pre-release versions (patch `.80`/`.85`/`.90`) never move this tag.

## Usage

This image is the control-plane component of the [OpenNebula Helm Chart](https://github.com/pablodelarco/opennebula-helm), designed to run on Kubernetes with hypervisor nodes attached externally. See the chart repository for deployment instructions.

```bash
docker pull pablodelarco/opennebula:__ONE_VERSION__
```

## Notes

- Community-maintained image, built automatically from the [opennebula-helm](https://github.com/pablodelarco/opennebula-helm) repository. Not an official OpenNebula Systems release.
- Every release is scanned with Trivy (CRITICAL/HIGH gate) before publishing.
- This description is updated automatically by CI on each release.

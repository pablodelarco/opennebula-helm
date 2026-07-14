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

Current releases follow the standard SemVer tagging convention:

| Tag | Meaning | Mutability |
|-----|---------|------------|
| `X.Y.Z` (e.g. `__ONE_VERSION__`) | a specific OpenNebula release | immutable |
| `latest` | newest **stable** release | floating |

- The image is verified at build time to contain exactly the OpenNebula version it is tagged as.
- Version tags are always the full `X.Y.Z` form — there are intentionally no abbreviated `X.Y` or `X` floating aliases. Crossing versions can require a database schema migration, so pin an exact release (`X.Y.Z`) rather than auto-rolling.
- Pre-release versions (patch `.80`/`.85`/`.90`) never move `latest`.
- **Legacy tags** dated 2021 (e.g. `6.2.0-1.ce-202111022053`, `6.0.0.3`) are the original OpenNebula Systems images, kept for historical reference. New releases use the scheme above.

## Usage

This image is the control-plane component of the [OpenNebula Helm Chart](https://github.com/pablodelarco/opennebula-helm), designed to run on Kubernetes with hypervisor nodes attached externally. See the chart repository for deployment instructions.

```bash
docker pull opennebula/opennebula:__ONE_VERSION__
```

## Notes

- Built automatically from the [opennebula-helm](https://github.com/pablodelarco/opennebula-helm) repository, tracking the newest stable OpenNebula release.
- The image content is verified at build time to contain exactly the OpenNebula version it is tagged as.
- Every release is scanned with Trivy (CRITICAL/HIGH gate) before publishing.
- This description is updated automatically by CI on each release.

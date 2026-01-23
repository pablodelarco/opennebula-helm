# Stack Research: OpenNebula Containerization

**Domain:** Infrastructure Management Platform Containerization
**Researched:** 2026-01-23
**Confidence:** HIGH (official docs, existing implementation, multiple community sources)

## Recommended Stack

### Container Base Images

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Ubuntu | 24.04 LTS (Noble) | Base image | Official OpenNebula support for 24.04 LTS; glibc-based (broad compatibility); extensive package availability; long-term security updates until 2034; smaller than Debian 12 (~76MB vs ~117MB compressed) |
| Ubuntu | 22.04 LTS (Jammy) | Alternative base | Current proven base in existing Dockerfile; will be supported until 2027 (extended to 2032); OpenNebula 6.10 officially supports it |

**Decision:** Use **Ubuntu 24.04** for new builds. The user's existing image uses 22.04 which is still supported, but 24.04 offers:
- Longer support window
- Latest security patches
- Officially supported by OpenNebula 6.10
- Production-ready for Docker (widely adopted in 2025)

### OpenNebula Version

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| OpenNebula | 6.10.x LTS | Cloud management platform | Latest LTS release; full FireEdge UI support; Prometheus monitoring included in Community Edition; active maintenance (6.10.5 released Nov 2025) |

**Note:** OpenNebula 7.x exists (released July 2025) but 6.10 LTS is recommended for:
- Production stability
- Longer support cycle
- Better community knowledge base
- 7.2 scheduled for January 2026 - evaluate after release

### OpenNebula Packages (Frontend)

| Package | Purpose | Required |
|---------|---------|----------|
| `opennebula` | Core daemon (oned) and scheduler | Yes |
| `opennebula-sunstone` | Legacy web UI | Optional (FireEdge preferred) |
| `opennebula-fireedge` | Next-gen web UI (replaces Sunstone) | Yes |
| `opennebula-gate` | VM-to-OpenNebula communication | Yes (for VM contextualization) |
| `opennebula-flow` | Multi-VM service orchestration | Yes |
| `opennebula-provision` | Edge cluster provisioning | Optional |
| `opennebula-rubygems` | Bundled Ruby dependencies | Yes (avoids system gem conflicts) |

### Database

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| MariaDB | 10.11+ (LTS) | Backend database | Official recommendation over SQLite for production; subchart integration via Bitnami; widely deployed |

**Important:** SQLite is default but NOT recommended for production. MariaDB subchart provides:
- HA capability
- Better performance under load
- Proper transaction support
- Backup/restore tooling

### Build Tools

| Tool | Version | Purpose | Why Recommended |
|------|---------|---------|-----------------|
| Docker Buildx | Latest | Multi-arch builds | Native BuildKit support; cache mounts; multi-platform (amd64/arm64) |
| BuildKit | Default in Docker 23+ | Build backend | Parallel builds; cache mounts for apt; better layer caching |

### CI/CD Stack

| Tool | Purpose | Why Recommended |
|------|---------|-----------------|
| GitHub Actions | Build automation | Native GHCR integration; existing workflow in repo |
| docker/build-push-action | Build and push | Standard pattern; multi-arch support |
| docker/metadata-action | Tag generation | Automatic semver, SHA, latest tags |
| docker/login-action | Registry auth | Works with GHCR and Docker Hub |
| aquasecurity/trivy-action | Security scanning | Already in existing workflow; catches CVEs |

### Container Registry

| Technology | Purpose | Why Recommended |
|------------|---------|-----------------|
| GHCR (ghcr.io) | Primary registry | Free for public; integrated with GitHub Actions; no rate limits for auth users |
| Docker Hub | Secondary/mirror | Broader reach; user already has `pablodelarco/opennebula-frontend` |

**Recommendation:** Use GHCR as primary (better GitHub integration), mirror to Docker Hub for discoverability.

### Dependency Management

| Tool | Purpose | Why Recommended |
|------|---------|-----------------|
| Renovate | Auto-update dependencies | Updates base image digests; Dockerfile FROM updates; Helm subchart versions |

## Dockerfile Patterns

### Recommended Multi-Stage Pattern

```dockerfile
# syntax=docker/dockerfile:1.6
# ^^^ Enables BuildKit features including cache mounts

# Stage 1: Package installation (can be cached separately)
FROM ubuntu:24.04 AS packages

ENV DEBIAN_FRONTEND=noninteractive

# Use BuildKit cache mount for apt
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      gnupg2 wget ca-certificates

# Add OpenNebula repository
RUN mkdir -p /etc/apt/keyrings && \
    wget -q -O- https://downloads.opennebula.io/repo/repo2.key | \
    gpg --dearmor --yes --output /etc/apt/keyrings/opennebula.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/opennebula.gpg] https://downloads.opennebula.io/repo/6.10/Ubuntu/24.04 stable opennebula" \
    > /etc/apt/sources.list.d/opennebula.list

# Install OpenNebula packages
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    RUNLEVEL=1 apt-get install -y --no-install-recommends \
      opennebula \
      opennebula-fireedge \
      opennebula-gate \
      opennebula-flow \
      opennebula-sunstone

# Stage 2: Runtime (cleaner final image)
FROM ubuntu:24.04 AS runtime

# Copy installed packages from build stage
COPY --from=packages /etc/one /etc/one
COPY --from=packages /usr/lib/one /usr/lib/one
COPY --from=packages /usr/share/one /usr/share/one
COPY --from=packages /var/lib/one /var/lib/one
# ... additional paths as needed

# Runtime configuration
# ...
```

**Note:** Multi-stage has limited benefit for OpenNebula because packages are pre-compiled. The primary value is:
- Separate apt cache from final image
- Cleaner layer history
- Option to add test stages

### Single-Stage Pattern (Simpler, Recommended for Now)

For OpenNebula specifically, single-stage with BuildKit cache mounts is sufficient:

```dockerfile
# syntax=docker/dockerfile:1.6
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Use BuildKit cache mounts for faster rebuilds
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      gnupg2 wget ca-certificates openssh-server sudo && \
    # Add OpenNebula repo and install
    # ... rest of installation
```

## GitHub Actions Workflow Pattern

```yaml
name: Build and Push

on:
  push:
    branches: [main]
    tags: ['v*']
  schedule:
    - cron: '0 0 * * 0'  # Weekly rebuild for security updates

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      attestations: write
      id-token: write

    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-qemu-action@v3

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/metadata-action@v5
        id: meta
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha

      - uses: docker/build-push-action@v5
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Ubuntu 24.04 | Debian 12 (Bookworm) | Need Debian specifically; slightly larger but equally stable |
| Ubuntu 24.04 | Alpine | NOT RECOMMENDED - OpenNebula requires glibc; many packages unavailable; Ruby/Node.js compatibility issues |
| Ubuntu 24.04 | Ubuntu 22.04 | Want proven stability; existing images; supporting older nodes |
| GHCR | Docker Hub | Need maximum discoverability; existing Docker Hub audience |
| Renovate | Dependabot | Simpler config; fewer features; GitHub-native |
| MariaDB subchart | Bundled SQLite | Testing/evaluation only; NOT for production |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Alpine base image | musl libc incompatibility with OpenNebula packages; Ruby gems may fail; glibc-dependent binaries | Ubuntu 24.04 |
| OpenNebula 7.x | Very new (July 2025); limited community experience; 7.2 not yet released | OpenNebula 6.10 LTS |
| SQLite in production | Single-file database; no HA; poor concurrent performance | MariaDB subchart |
| Building from source | Complex dependencies; long build times; difficult to maintain | Official packages from OpenNebula repo |
| Dockerfile HEALTHCHECK | Ignored by Kubernetes; use Kubernetes probes instead | livenessProbe, readinessProbe, startupProbe in Helm |
| Non-LTS Ubuntu | Shorter support; EOL surprises | Ubuntu 22.04 or 24.04 LTS |
| Legacy Sunstone alone | Ruby-based; deprecated; limited features | FireEdge (modern React-based UI) |

## Stack Patterns by Variant

**If targeting homelab:**
- Single container with all services
- SQLite acceptable for < 10 VMs
- Skip multi-arch (usually amd64 only)
- Simpler Helm values

**If targeting production:**
- Consider separate containers per service (kvaps pattern)
- MariaDB required
- HA frontend setup
- Multi-arch builds (amd64 + arm64)
- Full observability stack

**If migrating from VMware:**
- Include OpenNebula 6.10+ (has OneSwap tool)
- FireEdge UI essential
- Provision package for hybrid cloud

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| OpenNebula 6.10 | Ubuntu 22.04, 24.04 | Officially supported |
| OpenNebula 6.10 | Debian 11, 12 | Supported but no VMware infra management |
| OpenNebula 6.10 | RHEL/AlmaLinux 8, 9 | Full support |
| MariaDB 10.11+ | OpenNebula 6.x | LTS version; use Bitnami subchart |
| Ruby gems | opennebula-rubygems package | Use bundled gems, not system |

## Renovate Configuration for Auto-Updates

```json
{
  "extends": [
    "config:recommended",
    "docker:pinDigests",
    ":automergeDigest",
    ":automergePatch"
  ],
  "packageRules": [
    {
      "matchDatasources": ["docker"],
      "matchPackageNames": ["ubuntu"],
      "groupName": "ubuntu base image",
      "automerge": true
    }
  ]
}
```

## Sources

### Official Documentation (HIGH confidence)
- [OpenNebula 6.10 Platform Notes](https://docs.opennebula.io/6.10/intro_release_notes/release_notes/platform_notes.html) - Supported platforms
- [OpenNebula 6.8/6.10 Build Dependencies](https://docs.opennebula.io/6.8/integration_and_development/references/build_deps.html) - Package requirements
- [OpenNebula Frontend Installation](https://docs.opennebula.io/6.8/installation_and_configuration/frontend_installation/install.html) - Package list
- [Docker Multi-stage Builds](https://docs.docker.com/build/building/multi-stage/) - Build patterns
- [Docker BuildKit Cache](https://docs.docker.com/build/cache/optimize/) - Cache optimization

### Community Sources (MEDIUM confidence)
- [kvaps/kube-opennebula](https://github.com/kvaps/kube-opennebula) - Existing Helm chart with Dockerfiles
- [Docker Hub opennebula/opennebula](https://hub.docker.com/r/opennebula/opennebula) - Official OpenNebula image reference

### Ecosystem Research (MEDIUM confidence)
- [Alpine vs Ubuntu Base Images](https://jfrog.com/learn/cloud-native/docker-ubuntu-base-image/) - Base image comparison
- [GitHub Actions Docker Publishing](https://docs.github.com/actions/guides/publishing-docker-images) - CI/CD patterns
- [Renovate Docker Documentation](https://docs.renovatebot.com/docker/) - Auto-update configuration

### Existing Implementation (HIGH confidence)
- User's existing Dockerfile at `/home/pablo/kubernetes/kubernetes-homelab/apps/opennebula/docker_opennebula/Dockerfile`
- Uses Ubuntu 22.04, OpenNebula 6.10 packages
- Single-stage build pattern
- All-in-one container with oned, sunstone, fireedge, flow, gate

---
*Stack research for: OpenNebula Containerization*
*Researched: 2026-01-23*

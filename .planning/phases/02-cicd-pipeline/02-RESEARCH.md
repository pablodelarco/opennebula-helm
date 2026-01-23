# Phase 2: CI/CD Pipeline - Research

**Researched:** 2026-01-23
**Domain:** GitHub Actions, Docker Hub, Container Security Scanning
**Confidence:** HIGH

## Summary

This phase implements a CI/CD pipeline using GitHub Actions to build Docker images, push to Docker Hub, scan for vulnerabilities with Trivy, and detect new OpenNebula releases. The ecosystem has mature, well-documented official actions from Docker (`docker/build-push-action@v6`, `docker/metadata-action@v5`, `docker/login-action@v3`) and Aqua Security (`aquasecurity/trivy-action`).

The key design challenge is detecting new OpenNebula releases. OpenNebula does not use GitHub Releases - they use Git tags with format `release-X.Y.Z` and a package repository at `downloads.opennebula.io/repo/`. The recommended approach is a scheduled workflow that polls the OpenNebula repository, compares against a tracked version file, and triggers builds when new versions are detected.

**Primary recommendation:** Use official Docker actions with Trivy scanning, scheduled polling for OpenNebula releases, and semantic version tagging aligned with OpenNebula versions.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library/Tool | Version | Purpose | Why Standard |
|--------------|---------|---------|--------------|
| docker/build-push-action | v6 | Build and push Docker images with BuildKit | Official Docker action, full BuildKit support |
| docker/login-action | v3 | Authenticate to Docker Hub | Official Docker action for registry auth |
| docker/metadata-action | v5 | Generate tags and labels from Git context | Official, handles semver/latest/sha tagging |
| docker/setup-buildx-action | v3 | Set up Docker Buildx for advanced builds | Required for multi-platform and caching |
| aquasecurity/trivy-action | 0.33.1+ | Vulnerability scanning for containers | Industry standard, GitHub-native integration |
| actions/checkout | v4/v5 | Checkout repository code | GitHub official, required for context builds |

### Supporting
| Library/Tool | Version | Purpose | When to Use |
|--------------|---------|---------|-------------|
| actions/cache | v4 | Cache dependencies/state | Speed up builds, cache Trivy DB |
| github/codeql-action/upload-sarif | v4 | Upload scan results to Security tab | Optional: enhanced security visibility |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| docker/build-push-action | depot/build-push-action | Depot is faster but requires external service |
| Trivy | Snyk, Grype | Trivy is free, native GitHub integration, widely adopted |
| Polling downloads.opennebula.io | Polling GitHub tags | Both work; download page is authoritative for stable releases |

**Installation:** No installation needed - all GitHub Actions are referenced directly in workflow files.

## Architecture Patterns

### Recommended Workflow Structure
```
.github/
└── workflows/
    ├── docker-build.yml        # Main build workflow (push/tag/schedule)
    └── check-release.yml       # Scheduled version check (optional: can be in same file)
```

### Pattern 1: Multi-Trigger Docker Build Workflow
**What:** Single workflow that handles push, tag, schedule, and manual triggers
**When to use:** Always - consolidates build logic in one place

**Example:**
```yaml
# Source: https://docs.docker.com/build/ci/github-actions/
name: Docker Build

on:
  push:
    branches: [main]
    paths:
      - 'docker/**'
      - '.github/workflows/docker-build.yml'
  workflow_dispatch:
    inputs:
      opennebula_version:
        description: 'OpenNebula version to build'
        required: false
        type: string
  schedule:
    # Run daily at 3:15 AM UTC (off-peak time)
    - cron: '15 3 * * *'

env:
  REGISTRY: docker.io
  IMAGE_NAME: pablodelarco/opennebula-frontend

jobs:
  check-version:
    runs-on: ubuntu-latest
    outputs:
      should_build: ${{ steps.check.outputs.should_build }}
      version: ${{ steps.check.outputs.version }}
    steps:
      - name: Check for new OpenNebula version
        id: check
        run: |
          # Get latest version from OpenNebula repo
          LATEST=$(curl -s https://downloads.opennebula.io/repo/ | \
            grep -oP 'href="7\.[0-9]+\.[0-9]+/"' | \
            grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | \
            sort -V | tail -1)

          # Check if Docker Hub already has this version
          # Use workflow_dispatch input if provided
          if [ -n "${{ github.event.inputs.opennebula_version }}" ]; then
            LATEST="${{ github.event.inputs.opennebula_version }}"
          fi

          echo "version=${LATEST}" >> $GITHUB_OUTPUT
          echo "should_build=true" >> $GITHUB_OUTPUT

  build:
    needs: check-version
    if: needs.check-version.outputs.should_build == 'true'
    runs-on: ubuntu-latest
    # ... build steps
```

### Pattern 2: Semantic Version Tagging with Metadata Action
**What:** Generate multiple tags (7.0.1, 7.0, 7, latest) from a single version
**When to use:** Always - provides flexibility for consumers

**Example:**
```yaml
# Source: https://github.com/docker/metadata-action
- name: Docker meta
  id: meta
  uses: docker/metadata-action@v5
  with:
    images: ${{ env.IMAGE_NAME }}
    tags: |
      type=raw,value=${{ needs.check-version.outputs.version }}
      type=raw,value=latest,enable=${{ github.ref == 'refs/heads/main' }}
      type=sha,prefix=
```

### Pattern 3: Trivy Fail-Fast Scanning
**What:** Scan image before push, fail on CRITICAL/HIGH vulnerabilities
**When to use:** Always - security gate before publishing

**Example:**
```yaml
# Source: https://github.com/aquasecurity/trivy-action
- name: Build image for scanning
  uses: docker/build-push-action@v6
  with:
    context: ./docker
    load: true  # Load to local Docker, don't push yet
    tags: ${{ env.IMAGE_NAME }}:scan

- name: Run Trivy vulnerability scanner
  uses: aquasecurity/trivy-action@0.33.1
  with:
    image-ref: ${{ env.IMAGE_NAME }}:scan
    format: 'table'
    exit-code: '1'
    ignore-unfixed: true
    severity: 'CRITICAL,HIGH'
```

### Pattern 4: OpenNebula Release Detection via Repository Polling
**What:** Check OpenNebula downloads page for new versions
**When to use:** Scheduled workflow to trigger builds on new releases

**Example:**
```yaml
- name: Check for new OpenNebula release
  id: check
  run: |
    # Get latest stable version from downloads page
    LATEST=$(curl -s https://downloads.opennebula.io/repo/ | \
      grep -oP 'href="7\.[0-9]+\.[0-9]+/"' | \
      grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | \
      sort -V | tail -1)

    echo "Latest OpenNebula version: ${LATEST}"

    # Check if we already have this image on Docker Hub
    # Returns 0 if exists, 1 if not
    if docker manifest inspect pablodelarco/opennebula-frontend:${LATEST} > /dev/null 2>&1; then
      echo "Image already exists for version ${LATEST}"
      echo "should_build=false" >> $GITHUB_OUTPUT
    else
      echo "New version detected: ${LATEST}"
      echo "should_build=true" >> $GITHUB_OUTPUT
      echo "version=${LATEST}" >> $GITHUB_OUTPUT
    fi
```

### Anti-Patterns to Avoid
- **Building without context:** Using Git context (default) when you need local file modifications - use `context: .` with checkout instead
- **Pushing before scanning:** Always scan BEFORE pushing to Docker Hub - use `load: true` to build locally first
- **Using `latest` tag in production:** Never deploy `latest` in production - always use specific version tags
- **Hardcoding versions in Dockerfile:** The OpenNebula version should be in the repo URL, which is already parameterized by major version (7.0)
- **Caching state between scheduled runs:** GitHub Actions cache expires after 7 days and is immutable - use Docker Hub manifest check instead

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Docker image tagging | Custom tag logic | docker/metadata-action | Handles semver, sha, branch, schedule patterns |
| Registry authentication | Manual docker login | docker/login-action | Secure secret handling, multiple registries |
| Multi-platform builds | Separate build jobs | docker/setup-buildx-action + platforms | Single job, proper manifest lists |
| Vulnerability scanning | Custom CVE database queries | aquasecurity/trivy-action | Updated DB, SARIF output, GitHub integration |
| Build caching | Manual layer management | cache-from/cache-to with gha type | GitHub Actions native cache integration |

**Key insight:** Docker provides a complete, tested action ecosystem. Custom solutions introduce maintenance burden and security risks.

## Common Pitfalls

### Pitfall 1: Scheduled Workflow Not Running
**What goes wrong:** Schedule trigger only runs on default branch, workflow disabled after 60 days of inactivity
**Why it happens:** GitHub disables scheduled workflows in inactive public repos to save resources
**How to avoid:**
- Keep repository active (any push resets the timer)
- Or use a separate repo/service to trigger via `repository_dispatch`
**Warning signs:** No scheduled runs in Actions tab despite cron being defined

### Pitfall 2: Docker Build Context Issues
**What goes wrong:** Build fails with "file not found" or changes not reflected
**Why it happens:** Default Git context bypasses checkout, so local file modifications are ignored
**How to avoid:** Use `context: ./docker` with explicit `actions/checkout` step when you need local files
**Warning signs:** "COPY failed: file not found" errors, or stale files in image

### Pitfall 3: Trivy Database Rate Limiting
**What goes wrong:** Trivy fails to download vulnerability database
**Why it happens:** GitHub Actions runners share IPs; heavy usage triggers rate limits
**How to avoid:** Enable Trivy's built-in caching (default) or use `cache: true` explicitly
**Warning signs:** "failed to download vulnerability DB" errors

### Pitfall 4: Push Failures on Concurrent Builds
**What goes wrong:** Race condition when schedule and push trigger overlap
**Why it happens:** Both try to push the same tag simultaneously
**How to avoid:** Use `concurrency` group with `cancel-in-progress: true`
**Warning signs:** "tag already exists" or "manifest unknown" errors

### Pitfall 5: Secret Exposure in Logs
**What goes wrong:** Docker Hub credentials or tokens appear in workflow logs
**Why it happens:** Using `echo` with secrets or not masking outputs
**How to avoid:** Always use `${{ secrets.* }}` syntax, never pass secrets to `echo` or `run` commands
**Warning signs:** Credentials visible in Actions logs (GitHub will warn)

### Pitfall 6: OpenNebula Version Detection Misses Patch Releases
**What goes wrong:** Only major versions detected (7.0 vs 7.0.1)
**Why it happens:** Regex pattern doesn't capture full semver
**How to avoid:** Use pattern `7\.[0-9]+\.[0-9]+` not just `7\.[0-9]+`
**Warning signs:** Missing patch releases on Docker Hub

## Code Examples

Verified patterns from official sources:

### Complete Docker Build Workflow
```yaml
# Source: https://docs.docker.com/build/ci/github-actions/
# Source: https://github.com/docker/build-push-action
name: Docker Build and Push

on:
  push:
    branches: [main]
    paths:
      - 'docker/**'
  workflow_dispatch:
    inputs:
      opennebula_version:
        description: 'OpenNebula version to build (e.g., 7.0.1)'
        required: false
        type: string
  schedule:
    - cron: '15 3 * * *'  # Daily at 3:15 AM UTC

concurrency:
  group: docker-build-${{ github.ref }}
  cancel-in-progress: true

env:
  REGISTRY: docker.io
  IMAGE_NAME: pablodelarco/opennebula-frontend

jobs:
  detect-version:
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.detect.outputs.version }}
      should_build: ${{ steps.detect.outputs.should_build }}
    steps:
      - name: Detect OpenNebula version
        id: detect
        run: |
          # Use input if provided, otherwise detect latest
          if [ -n "${{ github.event.inputs.opennebula_version }}" ]; then
            VERSION="${{ github.event.inputs.opennebula_version }}"
          else
            VERSION=$(curl -s https://downloads.opennebula.io/repo/ | \
              grep -oP 'href="7\.[0-9]+\.[0-9]+/"' | \
              grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | \
              sort -V | tail -1)
          fi
          echo "version=${VERSION}" >> $GITHUB_OUTPUT

          # For scheduled runs, check if image already exists
          if [ "${{ github.event_name }}" = "schedule" ]; then
            if docker manifest inspect ${{ env.IMAGE_NAME }}:${VERSION} > /dev/null 2>&1; then
              echo "should_build=false" >> $GITHUB_OUTPUT
            else
              echo "should_build=true" >> $GITHUB_OUTPUT
            fi
          else
            echo "should_build=true" >> $GITHUB_OUTPUT
          fi

  build-scan-push:
    needs: detect-version
    if: needs.detect-version.outputs.should_build == 'true'
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build for scanning
        uses: docker/build-push-action@v6
        with:
          context: ./docker
          load: true
          tags: ${{ env.IMAGE_NAME }}:scan

      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@0.33.1
        with:
          image-ref: ${{ env.IMAGE_NAME }}:scan
          format: 'table'
          exit-code: '1'
          ignore-unfixed: true
          severity: 'CRITICAL,HIGH'

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: ./docker
          push: true
          tags: |
            ${{ env.IMAGE_NAME }}:${{ needs.detect-version.outputs.version }}
            ${{ env.IMAGE_NAME }}:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

### Docker Hub Authentication Setup
```yaml
# Source: https://github.com/docker/login-action
- name: Login to Docker Hub
  uses: docker/login-action@v3
  with:
    username: ${{ secrets.DOCKERHUB_USERNAME }}
    password: ${{ secrets.DOCKERHUB_TOKEN }}
```

Required secrets in repository settings:
- `DOCKERHUB_USERNAME`: Docker Hub username (pablodelarco)
- `DOCKERHUB_TOKEN`: Docker Hub access token (NOT password - create at hub.docker.com/settings/security)

### Trivy with SARIF Upload (Optional Enhancement)
```yaml
# Source: https://github.com/aquasecurity/trivy-action
- name: Run Trivy and upload to Security tab
  uses: aquasecurity/trivy-action@0.33.1
  with:
    image-ref: ${{ env.IMAGE_NAME }}:scan
    format: 'sarif'
    output: 'trivy-results.sarif'

- name: Upload Trivy scan results
  uses: github/codeql-action/upload-sarif@v4
  with:
    sarif_file: 'trivy-results.sarif'
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| docker/build-push-action@v2 | docker/build-push-action@v6 | 2024 | New outputs, attestations, summaries |
| aquasecurity/trivy-action@master | aquasecurity/trivy-action@0.33.1 | 2025 | Pinned version, cache improvements |
| Manual tag generation | docker/metadata-action@v5 | 2023 | Standardized tagging patterns |
| actions/cache@v3 | actions/cache@v4/v5 | 2025 | New cache backend (v2), better performance |
| docker login command | docker/login-action@v3 | 2023 | Secure credential handling |

**Deprecated/outdated:**
- `aquasecurity/trivy-action@master`: Should pin to specific version (0.33.1+)
- Manual `docker build` and `docker push` commands: Use build-push-action instead
- Storing version in GitHub cache: Cache is immutable and expires - use manifest check

## Open Questions

Things that couldn't be fully resolved:

1. **OpenNebula Minor Version Handling**
   - What we know: OpenNebula repo has directories like `7.0/`, `7.0.0/`, `7.0.1/`
   - What's unclear: Whether to track all patch versions or just latest in each minor series
   - Recommendation: Track all patch versions (7.0.0, 7.0.1) as separate Docker tags

2. **Multi-Architecture Builds**
   - What we know: docker/build-push-action supports `platforms: linux/amd64,linux/arm64`
   - What's unclear: Whether OpenNebula packages exist for arm64
   - Recommendation: Start with amd64 only; add arm64 if OpenNebula supports it

3. **Build Frequency for Scheduled Runs**
   - What we know: Daily is common; OpenNebula releases every few months
   - What's unclear: Optimal frequency to balance responsiveness vs API/build costs
   - Recommendation: Daily check at off-peak time (3:15 AM UTC)

## Sources

### Primary (HIGH confidence)
- [docker/build-push-action](https://github.com/docker/build-push-action) - Complete action documentation
- [docker/metadata-action](https://github.com/docker/metadata-action) - Tag generation patterns
- [docker/login-action](https://github.com/docker/login-action) - Registry authentication
- [aquasecurity/trivy-action](https://github.com/aquasecurity/trivy-action) - Vulnerability scanning configuration
- [Docker GitHub Actions documentation](https://docs.docker.com/build/ci/github-actions/) - Official best practices
- User's existing workflow at [pablodelarco/docker_opennebula](https://github.com/pablodelarco/docker_opennebula) - Working reference implementation

### Secondary (MEDIUM confidence)
- [GitHub Actions events documentation](https://docs.github.com/actions/learn-github-actions/events-that-trigger-workflows) - Trigger types
- OpenNebula GitHub tags API - Version format: `release-X.Y.Z`
- OpenNebula downloads repository (https://downloads.opennebula.io/repo/) - Authoritative version list

### Tertiary (LOW confidence)
- Community discussions on scheduled workflow reliability (GitHub Discussions)
- Docker Hub API for manifest inspection (undocumented but stable)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Official Docker and Trivy actions are well-documented
- Architecture: HIGH - Patterns verified against Docker official docs and user's existing workflow
- Pitfalls: MEDIUM - Based on community discussions and common issues

**Research date:** 2026-01-23
**Valid until:** 2026-04-23 (90 days - stable domain, GitHub Actions evolve slowly)

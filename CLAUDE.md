# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

One repository that produces **two coupled artifacts** for running OpenNebula's control plane on Kubernetes.

1. **A Docker image** (`opennebula/opennebula` on Docker Hub), built from `docker/`. An OpenNebula **front-end** (oned, one_sched, FireEdge, OneFlow, OneGate, OneForm, OneKS) packaged for containers.
2. **A Helm chart** (`opennebula`), in `charts/opennebula/`. Deploys that image as a single self-contained StatefulSet. No database subchart: OpenNebula runs on SQLite.

> Note: the local directory is named `opennebula-docker-image`, but the git remote and every documented URL point to `pablodelarco/opennebula-helm`. Same project: the chart is published to `https://pablodelarco.github.io/opennebula-helm` and the image to Docker Hub. There is no `LICENSE` file yet despite Apache-2.0 references in the READMEs.
>
> Image namespace: the image is published to **`opennebula/opennebula`**. It is **community-maintained and not an official OpenNebula Systems product**; both READMEs and the Docker Hub overview carry that disclaimer. The CaixaBank/EMERALD pilot pulls `opennebula/opennebula:7.2.0`, so **that exact tag must stay live** and must never be overwritten.

## Version is pinned in exactly one place

`docker/ONE_VERSION` (currently `7.4.0`) is the **single source of truth** for which OpenNebula release everything targets. It flows outward:

- `docker/Dockerfile` requires it as the `ONE_VERSION` build-arg (build fails fast if unset) and pins the apt repo to that exact release.
- `charts/opennebula/Chart.yaml` `appVersion` mirrors it; the image tag defaults to `appVersion` when `image.tag` is empty.
- `README.md` badges and the hypervisor-node apt repo URL are kept in sync automatically.

Never hand-edit the version in multiple files. The `version-watch` workflow does the coordinated bump (see below). `docker/README.md` is the Docker Hub description. CI still runs a `__ONE_VERSION__` substitution over it, so that placeholder can be used, but the file no longer depends on it.

## Architecture: why the image looks the way it does

**No systemd → supervisord.** OpenNebula's Ubuntu packages expect systemd to launch services. Containers have none, so `docker/supervisord.conf` runs the six long-lived processes directly: `oned` (priority 10, starts first), then `fireedge`, `oneflow`, `onegate`, `oneform-server` and `oneks-server` (priority 20). All run as `oneadmin`.

> The `/usr/bin/one*-server` binaries are `{start|stop}` wrappers that daemonise, which supervisord cannot manage. Invoke the Ruby entry point directly (`ruby /usr/lib/one/oneform/oneform-server.rb`), as the existing OneFlow and OneGate entries do.

**Everything logs to stdout.** Each program uses `stdout_logfile=/dev/fd/1` with `redirect_stderr=true`, and the entrypoint sets `LOG SYSTEM="std"` in `oned.conf`. Do not send service output back to files under `/var/log/one`: that is what previously made failures invisible to `kubectl logs`, leaving only supervisord lifecycle noise.

**`docker/entrypoint.sh` does everything systemd unit files + post-install scripts normally would**, at container start, before `exec`-ing supervisord. Read it in full before changing runtime behavior. Its responsibilities:
- **Bootstrap detection** via presence of `/var/lib/one/.one/one_key`. Fresh install → wipe stale auth files and write `one_auth` with `ONEADMIN_PASSWORD` *before* oned bootstraps (so oned adopts that password). Existing install → leave the DB alone.
- **MySQL config injection**: when `DB_BACKEND=mysql`, a `sed` block rewrites the entire `DB = [ ... ]` stanza in `/etc/one/oned.conf` from env vars (`DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`).
- **Schema upgrade**: runs `onedb upgrade --backup` on existing installs (no-op if current; backups land in `/var/lib/one/backups/db`). This is what lets an image version bump cross a DB schema change.
- **Container-networking fixes**: forces OneFlow/OneGate to listen on `0.0.0.0`, sets `HOSTNAME` (from `OPENNEBULA_HOSTNAME`) and `MONITOR_ADDRESS` (from `OPENNEBULA_MONITOR_ADDRESS`) so hypervisors get a reachable address instead of an internal pod IP, and leaves `SCHED_MAD` **enabled**. The scheduler is required: without `one_sched` every VM stays PENDING forever, including on the remote hosts this front-end exists to manage.
- **Ownership repair** for fresh PersistentVolume mounts.

**The PV hides everything the packages put in `/var/lib/one`.** The volume mounts over that path, so packaged content disappears at runtime. Two mechanisms cover it:
- `remotes-dist`: the Dockerfile copies `remotes/` to `/usr/share/one/remotes-dist`; the entrypoint restores it when missing.
- `one-skel`: the Dockerfile snapshots the whole of `/var/lib/one` to `/usr/share/one/one-skel` **after installing every package**; the entrypoint seeds only missing entries (`cp -a -n`), never overwriting state. This is what makes OneKS work, since its controlplane families live under `/var/lib/one/oneks/`.

Any new package that installs under `/var/lib/one` is covered automatically, **provided the snapshot stays after the package install step** in the Dockerfile.

**Slimming:** the Dockerfile deletes `npm`/`corepack` after install, because FireEdge runs its prebuilt app with the bare `node` binary, so they're pure attack surface. If a version bump changes how FireEdge is packaged, re-verify this removal (the release-analysis checklist flags it).

## Architecture: the Helm chart

- **StatefulSet, 1 replica** (`templates/statefulset.yaml`). Stable identity matters because oned advertises its FQDN to hypervisors, which is also why the **headless** Service exists. Liveness/readiness both use `oneuser show 0`, a real XML-RPC check, so a pod whose oned has died is correctly marked unready.
- **FireEdge `__HOST__` proxy** (`templates/configmap-proxy.yaml` + the `fireedge-proxy` nginx sidecar). FireEdge bakes a literal `__HOST__` placeholder into its served JS. The nginx sidecar `sub_filter`s it to the real access URL (`$scheme://$http_host` by default). This is why the web UI works transparently across port-forward / NodePort / LoadBalancer / Ingress. Disabling `fireedgeProxy` breaks the UI unless you supply your own sub_filter proxy.
- **Two services** (`templates/service.yaml`): a headless service for StatefulSet identity + monitord/ssh, and the main service for the UI and APIs. Monitord is exposed on `4124` over **both TCP and UDP**.
- **Password persistence** (`templates/secret.yaml`): uses `lookup` + `helm.sh/resource-policy: keep` so generated admin/DB passwords survive `helm upgrade` instead of being regenerated.
- **No DB helpers.** The chart sets `DB_BACKEND=sqlite` and nothing else; there is no database subchart, secret or init container. To use an external MySQL, set the `DB_*` environment variables on the image directly.

## CI/CD pipeline (three workflows)

1. **`version-watch.yml`** (nightly cron + manual). Scrapes `downloads.opennebula.io` for the newest *stable* release (patch `< 80`; `.80/.85/.90` are pre-releases and skipped). If newer than the pin, runs `.github/scripts/analyze-release.sh` and opens a **bump PR** editing `docker/ONE_VERSION`, `Chart.yaml` (`appVersion` + patch-bumped chart `version`), and `README.md`. Nothing builds until a human merges. Also pushes an empty keepalive commit if the repo has been idle ~50 days (GitHub disables cron workflows after 60).
2. **`docker-build.yml`** (push to `docker/**`, or manual dispatch with a version). Builds → **verifies the installed `dpkg` version equals the tag** (guards against tag/content drift) → **Trivy scan** gating on CRITICAL/HIGH (`docker/.trivyignore`) → pushes `X.Y.Z`. `:latest` and the Docker Hub description update **only when building the pinned version** (`is_latest`), so dispatch rebuilds of old/pre-release versions can't regress them.
3. **`release-chart.yaml`** (push to `charts/**`). Packages the chart, creates a GitHub release `opennebula-<chartVersion>`, and regenerates `index.yaml` on the `gh-pages` branch (the Helm repo).

**Tagging philosophy:** only immutable full `X.Y.Z` tags plus floating `:latest`. No `X.Y` or bare-major aliases, because crossing versions can require a DB migration, so operators pin exactly.

**`.github/scripts/analyze-release.sh`** is the review aid: it diffs two releases' apt package versions, dependencies, file manifests (`opennebula`, `opennebula-fireedge`), and `/etc/one` configs, then emits a markdown **adaptation checklist**. When changing anything the entrypoint's `sed` edits depend on, consult that checklist; those edits are format-fragile against upstream config changes.

## Common commands

```bash
# Build the image locally (ONE_VERSION build-arg is REQUIRED)
docker build --build-arg ONE_VERSION=$(cat docker/ONE_VERSION) \
  -t opennebula/opennebula:$(cat docker/ONE_VERSION) ./docker

# Verify the image contains the version it claims (what CI gates on)
docker run --rm --entrypoint dpkg-query opennebula/opennebula:7.4.0 \
  -W -f='${Version}' opennebula

# Trivy scan the way CI does
trivy image --severity CRITICAL,HIGH --ignore-unfixed \
  --trivyignores docker/.trivyignore opennebula/opennebula:7.4.0

# Generate a release-adaptation report between two versions
.github/scripts/analyze-release.sh 7.0.0 7.2.0

# --- Helm chart ---
# the chart has no dependencies, so no 'helm dependency update' is needed
helm lint charts/opennebula
helm template opennebula charts/opennebula     # render manifests locally
helm template opennebula charts/opennebula -f my-values.yaml
helm package charts/opennebula --destination /tmp/packages

# Install / test a running release
helm install opennebula charts/opennebula
helm test opennebula                           # runs templates/tests/test-connection.yaml
```

There is no unit-test framework, linter config, or Makefile in this repo. Validation is: `helm lint`/`helm template` for the chart, the build-time version check + Trivy gate for the image, and the `helm test` connection hook for a live deployment.

## Gotchas

- **`/var/lib/one` is a mount point.** Anything a package installs there is invisible at runtime unless it is in the `one-skel` snapshot, and that snapshot must be taken **after** the OpenNebula packages are installed in the Dockerfile. Taking it earlier silently produces an image where OneKS cannot start.
- **OneKS requires TPROXY.** It refuses to start unless `:tproxy:` is configured in `/var/lib/one/remotes/etc/vnm/OpenNebulaNetwork.conf`; the entrypoint appends it. Its cluster router relies on the link-local address `169.254.16.9` so guest VMs can reach OneGate and XML-RPC.
- **OneForm and OneKS carry exact-version dependencies** (`Depends: opennebula (= X.Y.Z-1)`), so they cannot be upgraded independently of the core. `AUTO_UPDATE_ADDONS` therefore only picks up patch releases inside the built series.
- **`scripts/version-check/` is a separate, local macOS convenience tool** (desktop notifications via `osascript`), not part of CI. Its `check.log` and `last_seen_version` are committed state artifacts. The authoritative automation is `version-watch.yml`.
- **`docker/README.md` `__ONE_VERSION__` placeholders** are rendered by CI at publish time; leave them literal.
- Changing `entrypoint.sh` `sed` targets, `supervisord.conf` binary paths, or the Dockerfile package list is exactly what the `analyze-release.sh` adaptation checklist exists to re-verify after an upstream version bump.

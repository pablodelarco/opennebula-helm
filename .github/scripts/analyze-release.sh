#!/usr/bin/env bash
# Compare two OpenNebula releases and emit a markdown adaptation report.
# Downloads the apt package indexes and the main debs for both versions,
# then diffs package versions, dependencies, file manifests, and the
# /etc/one configuration files. Used as the body of version-bump PRs so
# every release gets reviewed for changes that need tailoring in the
# Dockerfile, entrypoint, or Helm chart.
#
# Usage: analyze-release.sh <old-version> <new-version>
set -euo pipefail

OLD="$1"
NEW="$2"
BASE="https://downloads.opennebula.io/repo"
DIST="Ubuntu/24.04"
PACKAGES="opennebula opennebula-fireedge opennebula-flow opennebula-gate opennebula-tools"
# Packages whose payloads are downloaded and diffed in depth (the ones the
# Dockerfile and entrypoint make assumptions about)
DEEP_PACKAGES="opennebula opennebula-fireedge"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fetch_index() { # <version> -> writes $WORK/Packages.<version>
    curl -fsSL "$BASE/$1/$DIST/dists/stable/opennebula/binary-amd64/Packages" \
        > "$WORK/Packages.$1"
}

pkg_field() { # <version> <package> <field>
    awk -v p="$2" -v f="$3" '
        $0 == "Package: " p {found=1; next}
        found && $0 ~ "^" f ": " {sub("^" f ": ", ""); print; exit}
        found && /^$/ {exit}
    ' "$WORK/Packages.$1"
}

extract_deb() { # <deb-file> <target-dir>
    local deb="$1" dir="$2" comp
    mkdir -p "$dir"
    for comp in data.tar.zst data.tar.xz data.tar.gz; do
        if ar p "$deb" "$comp" > "$dir/payload" 2>/dev/null && [ -s "$dir/payload" ]; then
            case "$comp" in
                *.zst) zstd -dqc "$dir/payload" | tar -x -C "$dir" ;;
                *.xz)  xz -dc "$dir/payload" | tar -x -C "$dir" ;;
                *.gz)  gzip -dc "$dir/payload" | tar -x -C "$dir" ;;
            esac
            rm -f "$dir/payload"
            return 0
        fi
    done
    echo "ERROR: could not extract $deb" >&2
    return 1
}

fetch_and_extract() { # <version> <package>
    local ver="$1" pkg="$2" filename
    filename=$(pkg_field "$ver" "$pkg" "Filename")
    if [ -z "$filename" ]; then
        echo "ERROR: package $pkg not found in $ver index" >&2
        return 1
    fi
    curl -fsSL "$BASE/$ver/$DIST/$filename" -o "$WORK/$pkg-$ver.deb"
    extract_deb "$WORK/$pkg-$ver.deb" "$WORK/root-$pkg-$ver"
}

file_list() { # <version> <package> -> sorted relative paths
    (cd "$WORK/root-$1-$2" 2>/dev/null && find . -type f -o -type l | sed 's|^\./||' | sort) || true
}

fetch_index "$OLD"
fetch_index "$NEW"

echo "## OpenNebula ${OLD} -> ${NEW} release analysis"
echo
echo "Automated comparison of the upstream packages. Review each section"
echo "for changes that need tailoring before merging this version bump."
echo
echo "**Upstream references:**"
echo "- Release notes: https://github.com/OpenNebula/one/releases/tag/release-${NEW}"
echo "- Documentation: https://docs.opennebula.io/${NEW%.*}/"
echo

echo "### Package versions"
echo
echo "| Package | ${OLD} | ${NEW} |"
echo "|---------|--------|--------|"
for pkg in $PACKAGES; do
    echo "| $pkg | $(pkg_field "$OLD" "$pkg" Version) | $(pkg_field "$NEW" "$pkg" Version) |"
done
echo

echo "### Dependency changes"
echo
DEP_CHANGES=0
for pkg in $PACKAGES; do
    OLD_DEPS=$(pkg_field "$OLD" "$pkg" Depends | tr ',' '\n' | sed 's/^ *//' | sort)
    NEW_DEPS=$(pkg_field "$NEW" "$pkg" Depends | tr ',' '\n' | sed 's/^ *//' | sort)
    if [ "$OLD_DEPS" != "$NEW_DEPS" ]; then
        DEP_CHANGES=1
        echo "**${pkg}:**"
        echo '```diff'
        diff <(echo "$OLD_DEPS") <(echo "$NEW_DEPS") | grep '^[<>]' | sed 's/^</-/; s/^>/+/' || true
        echo '```'
        echo
    fi
done
[ "$DEP_CHANGES" = 0 ] && { echo "No dependency changes."; echo; }

for pkg in $DEEP_PACKAGES; do
    fetch_and_extract "$OLD" "$pkg" >&2
    fetch_and_extract "$NEW" "$pkg" >&2

    echo "### File manifest: ${pkg}"
    echo
    file_list "$OLD" "$pkg" > "$WORK/files-old"
    file_list "$NEW" "$pkg" > "$WORK/files-new"
    ADDED=$(comm -13 "$WORK/files-old" "$WORK/files-new")
    REMOVED=$(comm -23 "$WORK/files-old" "$WORK/files-new")
    # node_modules churn is huge and rarely actionable; report it as counts
    ADDED_NOTABLE=$(echo "$ADDED" | grep -v 'node_modules/' | grep . || true)
    REMOVED_NOTABLE=$(echo "$REMOVED" | grep -v 'node_modules/' | grep . || true)
    ADDED_NM=$(echo "$ADDED" | grep -c 'node_modules/' || true)
    REMOVED_NM=$(echo "$REMOVED" | grep -c 'node_modules/' || true)
    echo "Added: $(echo "$ADDED" | grep -c . || true) files, removed: $(echo "$REMOVED" | grep -c . || true) files (of which node_modules: +${ADDED_NM}/-${REMOVED_NM})."
    echo
    if [ -n "$ADDED_NOTABLE" ]; then
        echo "<details><summary>Added (excluding node_modules, first 100)</summary>"
        echo
        echo '```'
        echo "$ADDED_NOTABLE" | head -100
        echo '```'
        echo "</details>"
        echo
    fi
    if [ -n "$REMOVED_NOTABLE" ]; then
        echo "<details><summary>Removed (excluding node_modules, first 100)</summary>"
        echo
        echo '```'
        echo "$REMOVED_NOTABLE" | head -100
        echo '```'
        echo "</details>"
        echo
    fi
done

echo "### Configuration changes (/etc/one)"
echo
CONF_DIFF=$(diff -ru "$WORK/root-opennebula-$OLD/etc/one" "$WORK/root-opennebula-$NEW/etc/one" 2>/dev/null || true)
if [ -n "$CONF_DIFF" ]; then
    echo "<details><summary>Unified diff (first 300 lines)</summary>"
    echo
    echo '```diff'
    echo "$CONF_DIFF" | head -300
    echo '```'
    echo "</details>"
else
    echo "No configuration changes."
fi
echo

cat <<'CHECKLIST'
### Adaptation checklist

Verify each assumption this repo makes about the packages before merging:

- [ ] `docker/Dockerfile` package list still matches what the frontend needs
- [ ] npm/corepack removal still valid (FireEdge still runs its prebuilt app with the node binary only)
- [ ] `docker/entrypoint.sh` sed edits still match the config file formats (`oned.conf` DB block, `oneflow-server.conf`, `onegate-server.conf`, monitord `MONITOR_ADDRESS`, `SCHED_MAD` block)
- [ ] `docker/supervisord.conf` service commands still correct (oned, fireedge, oneflow, onegate paths)
- [ ] Database schema change? If oned requires a newer DB version, the entrypoint runs `onedb upgrade` automatically; confirm upgrade notes in the upstream release notes
- [ ] New CVEs at the Trivy gate: check the docker-build run on this PR's merge; tune `docker/.trivyignore` only for vendored binaries that upstream must rebuild
- [ ] Chart values/ports still match (new services or ports exposed upstream?)
- [ ] Hypervisor node instructions in README still match the frontend version

The docker-build workflow verifies at build time that the image contains
exactly the pinned version and gates publishing on the Trivy scan.
CHECKLIST

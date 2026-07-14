# OpenNebula Control Plane Docker Image
# Ubuntu 24.04 base with supervisord for process management (no systemd)

FROM ubuntu:24.04

# OpenNebula release to install (e.g. 7.2.0). Passed by CI from the detected
# release so the image content always matches the image tag. Required: the
# build fails fast when unset instead of silently installing a stale version.
ARG ONE_VERSION
RUN test -n "$ONE_VERSION" || { echo "ERROR: ONE_VERSION build-arg is required, e.g. --build-arg ONE_VERSION=7.2.0" >&2; exit 1; }
LABEL org.opencontainers.image.version="${ONE_VERSION}"

# Prevent interactive prompts during package installation
# RUNLEVEL=1 prevents services from starting during apt install
ENV DEBIAN_FRONTEND=noninteractive \
    RUNLEVEL=1

# Install prerequisites
# systemd provides systemd-tmpfiles required by OpenNebula post-install scripts
# sqlite3 used by entrypoint to check database bootstrap status
# mariadb-client provides mysqldump, needed by 'onedb upgrade --backup'
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg2 \
    wget \
    apt-transport-https \
    ca-certificates \
    supervisor \
    sudo \
    systemd \
    sqlite3 \
    mariadb-client \
    && rm -rf /var/lib/apt/lists/*

# Add OpenNebula repository pinned to the exact release version, so apt
# installs precisely the version the image tag claims
RUN mkdir -p /etc/apt/keyrings && \
    wget -qO- https://downloads.opennebula.io/repo/repo2.key | gpg --dearmor -o /etc/apt/keyrings/opennebula.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/opennebula.gpg] https://downloads.opennebula.io/repo/${ONE_VERSION}/Ubuntu/24.04 stable opennebula" > /etc/apt/sources.list.d/opennebula.list

# Install OpenNebula packages
# RUNLEVEL=1 prevents service auto-start during installation
# npm and corepack ship inside the nodejs package pulled in by fireedge but
# are not needed at runtime (FireEdge runs its prebuilt app with the node
# binary); remove them to keep the attack surface and image size down
RUN apt-get update && RUNLEVEL=1 apt-get install -y --no-install-recommends \
    opennebula \
    opennebula-fireedge \
    opennebula-flow \
    opennebula-gate \
    opennebula-tools \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/lib/node_modules/npm /usr/lib/node_modules/corepack \
       /usr/bin/npm /usr/bin/npx /usr/bin/corepack

# Preserve remotes directory before PV mount overwrites it
# The remotes directory contains scheduler scripts needed by oned
RUN cp -a /var/lib/one/remotes /usr/share/one/remotes-dist

# Create required directories with proper ownership
RUN mkdir -p /var/log/one && \
    chown -R oneadmin:oneadmin /var/log/one && \
    mkdir -p /var/lib/one/.one && \
    chown -R oneadmin:oneadmin /var/lib/one/.one && \
    mkdir -p /var/lib/one/.ssh && \
    chown -R oneadmin:oneadmin /var/lib/one/.ssh && \
    chmod 700 /var/lib/one/.ssh

# Copy configuration files
COPY supervisord.conf /etc/supervisor/conf.d/opennebula.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose ports
# 2633 - oned XML-RPC API
# 2616 - FireEdge/Sunstone web UI
# 2474 - OneFlow API
# 5030 - OneGate API
# 4124 - Monitord (TCP+UDP for hypervisor monitoring probes)
# 22   - SSH (transfer manager, driver operations)
EXPOSE 2633 2616 2474 5030 4124 22

# Healthcheck using oneuser show command
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD oneuser show 0 || exit 1

# Set entrypoint and command
ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]

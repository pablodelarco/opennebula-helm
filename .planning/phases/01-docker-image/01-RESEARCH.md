# Phase 1: Docker Image - Research

**Researched:** 2026-01-23
**Domain:** OpenNebula 7.0 Docker containerization without systemd
**Confidence:** HIGH

## Summary

This research investigates how to containerize OpenNebula 7.0 control plane services (oned, Sunstone/FireEdge, OneFlow, OneGate) without systemd on Ubuntu 24.04. The user has an existing working Docker image for OpenNebula 6.10 that uses `RUNLEVEL=1` during installation and manual service starts in the entrypoint, which provides a proven pattern.

OpenNebula 7.0 packages are available for Ubuntu 24.04 from official repositories. Each service has a clear foreground command: `oned -f` for the daemon, `ruby /usr/lib/one/oneflow/oneflow-server.rb` for OneFlow, `ruby /usr/lib/one/onegate/onegate-server.rb` for OneGate, and `node /usr/lib/one/fireedge/dist/index.js` for FireEdge. The scheduler in 7.0 is no longer a persistent service (major change from 6.10) - it runs on demand, which simplifies containerization.

**Primary recommendation:** Use supervisord for process management (matching OpenNebula's official container approach), with SQLite as default database for easy testing and MySQL/MariaDB connection configurable via environment variables.

## Standard Stack

The established tools for this domain:

### Core Components

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Ubuntu | 24.04 LTS | Base image | Required by IMG-01, OpenNebula official support |
| OpenNebula | 7.0.0 | Cloud management platform | User requirement |
| supervisord | 4.x | Process manager | Used by official OpenNebula containers, replaces systemd |
| SQLite | 3.x (bundled) | Default database | Zero-config default, included with packages |

### OpenNebula Packages

| Package | Purpose | Service Provided |
|---------|---------|------------------|
| opennebula | Main daemon, XML-RPC API | oned |
| opennebula-fireedge | Web UI server (replaces old Sunstone) | fireedge (provides Sunstone) |
| opennebula-flow | Multi-VM orchestration | oneflow-server |
| opennebula-gate | VM-to-OpenNebula communication | onegate-server |
| opennebula-common | User oneadmin, common files | N/A |
| opennebula-tools | CLI tools (onevm, onehost, etc.) | N/A |
| opennebula-rubygems | Ruby dependencies | Required by flow/gate |

### Supporting Tools

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| gnupg2 | System | GPG key handling | Repository setup |
| wget | System | Download files | Repository key |
| apt-transport-https | System | HTTPS apt support | Repository access |
| openssh-server | System | SSH daemon | oneadmin SSH access |

**Installation:**
```bash
# Add OpenNebula repository
wget -q -O- https://downloads.opennebula.io/repo/repo2.key | gpg --dearmor --yes --output /etc/apt/keyrings/opennebula.gpg
echo "deb [signed-by=/etc/apt/keyrings/opennebula.gpg] https://downloads.opennebula.io/repo/7.0/Ubuntu/24.04 stable opennebula" > /etc/apt/sources.list.d/opennebula.list
apt-get update

# Install packages (with RUNLEVEL=1 to prevent systemd service starts)
RUNLEVEL=1 apt-get install -y opennebula opennebula-fireedge opennebula-flow opennebula-gate opennebula-tools
```

## Architecture Patterns

### Recommended Dockerfile Structure
```dockerfile
FROM ubuntu:24.04

# Prevent interactive prompts and systemd service starts
ENV DEBIAN_FRONTEND=noninteractive
ENV RUNLEVEL=1

# Install dependencies, add repo, install packages
# Configure oneadmin user
# Set up supervisord
# Configure services for container environment
# Expose ports
# Add entrypoint and healthcheck

ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
```

### Pattern 1: RUNLEVEL=1 Installation Pattern
**What:** Set RUNLEVEL=1 before installing OpenNebula packages to prevent systemd from starting services during installation
**When to use:** Always during Dockerfile build phase
**Source:** User's existing working 6.10 image
```dockerfile
ENV RUNLEVEL=1
RUN apt-get install -y opennebula opennebula-fireedge opennebula-flow opennebula-gate
```

### Pattern 2: Supervisord Process Management
**What:** Use supervisord to manage multiple services in a single container
**When to use:** When running multiple services (oned, fireedge, oneflow, onegate) in one container
**Source:** Official OpenNebula container approach (https://docs.opennebula.io/6.0/installation_and_configuration/containerized_deployment/reference.html)
```ini
# /etc/supervisor/conf.d/opennebula.conf
[program:oned]
command=/usr/bin/oned -f
user=oneadmin
autostart=true
autorestart=true
stdout_logfile=/var/log/one/oned.log
stderr_logfile=/var/log/one/oned.error

[program:fireedge]
command=/usr/bin/node /usr/lib/one/fireedge/dist/index.js
user=oneadmin
autostart=true
autorestart=true
stdout_logfile=/var/log/one/fireedge.log
stderr_logfile=/var/log/one/fireedge.error
depends_on=oned

[program:oneflow]
command=/usr/bin/ruby /usr/lib/one/oneflow/oneflow-server.rb
user=oneadmin
autostart=true
autorestart=true
stdout_logfile=/var/log/one/oneflow.log
stderr_logfile=/var/log/one/oneflow.error
depends_on=oned

[program:onegate]
command=/usr/bin/ruby /usr/lib/one/onegate/onegate-server.rb
user=oneadmin
autostart=true
autorestart=true
stdout_logfile=/var/log/one/onegate.log
stderr_logfile=/var/log/one/onegate.error
depends_on=oned
```

### Pattern 3: Environment Variable Configuration
**What:** Override config file values via environment variables in entrypoint
**When to use:** For database connection, passwords, endpoints
```bash
# In entrypoint.sh - modify oned.conf based on env vars
if [ -n "$DB_BACKEND" ]; then
  sed -i "s/BACKEND = \"sqlite\"/BACKEND = \"$DB_BACKEND\"/" /etc/one/oned.conf
fi
if [ "$DB_BACKEND" = "mysql" ]; then
  sed -i "s/SERVER = .*/SERVER = \"$DB_HOST\",/" /etc/one/oned.conf
  sed -i "s/USER = .*/USER = \"$DB_USER\",/" /etc/one/oned.conf
  sed -i "s/PASSWD = .*/PASSWD = \"$DB_PASSWORD\",/" /etc/one/oned.conf
  sed -i "s/DB_NAME = .*/DB_NAME = \"$DB_NAME\"/" /etc/one/oned.conf
fi
```

### Anti-Patterns to Avoid
- **Running systemctl in container:** systemd doesn't work in standard Docker containers - use direct commands
- **Installing without RUNLEVEL=1:** Packages will try to start services via systemd during install, causing failures
- **Hardcoding oneadmin password:** Use environment variable for the one_auth credentials
- **Single service per container without orchestration:** For this phase, all services in one container is the requirement

## Service Start Commands

Verified commands extracted from systemd service files:

| Service | Start Command | User | Port |
|---------|--------------|------|------|
| oned | `/usr/bin/oned -f` | oneadmin | 2633 |
| FireEdge (Sunstone) | `node /usr/lib/one/fireedge/dist/index.js` | oneadmin | 2616 |
| OneFlow | `ruby /usr/lib/one/oneflow/oneflow-server.rb` | oneadmin | 2474 |
| OneGate | `ruby /usr/lib/one/onegate/onegate-server.rb` | oneadmin | 5030 |

**Service Dependencies:**
- All services depend on oned being available
- FireEdge optionally uses guacd for remote console (not required for basic operation)
- Services must be started in order: oned first, then others

## Configuration Files

| File | Purpose | Key Settings to Expose |
|------|---------|----------------------|
| `/etc/one/oned.conf` | Main daemon config | DB backend, DB connection, LOG level |
| `/etc/one/fireedge-server.conf` | FireEdge/Sunstone config | Host, port, oned endpoint |
| `/etc/one/oneflow-server.conf` | OneFlow config | Host, port |
| `/etc/one/onegate-server.conf` | OneGate config | Host, port |
| `/var/lib/one/.one/one_auth` | oned authentication | oneadmin:password |
| `/var/lib/one/.one/oneflow_auth` | OneFlow authentication | serveradmin:password |
| `/var/lib/one/.one/onegate_auth` | OneGate authentication | serveradmin:password |

## Exposed Ports

| Port | Service | Protocol | Purpose |
|------|---------|----------|---------|
| 2633 | oned | TCP | XML-RPC API |
| 2616 | FireEdge | TCP | Web UI (Sunstone) |
| 2474 | OneFlow | TCP | Service orchestration API |
| 5030 | OneGate | TCP | VM communication API |
| 4124 | Monitoring | TCP/UDP | Host monitoring (not needed for control plane only) |

## Environment Variables Design

Recommended environment variables to expose:

| Variable | Default | Purpose |
|----------|---------|---------|
| `ONEADMIN_PASSWORD` | `oneadmin` | Password for oneadmin user |
| `DB_BACKEND` | `sqlite` | Database backend: sqlite or mysql |
| `DB_HOST` | `localhost` | MySQL server host |
| `DB_PORT` | `3306` | MySQL server port |
| `DB_USER` | `oneadmin` | MySQL username |
| `DB_PASSWORD` | `` | MySQL password |
| `DB_NAME` | `opennebula` | MySQL database name |
| `ONEGATE_ENDPOINT` | `http://localhost:5030` | OneGate endpoint for VMs |
| `LOG_LEVEL` | `3` | Logging verbosity (0-3) |

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Process management | Custom bash loop | supervisord | Handles restarts, logging, dependencies |
| Database migration | Custom scripts | onedb command | Handles schema migrations properly |
| Ruby dependencies | Manual gem install | opennebula-rubygems package | Pre-packaged, tested dependencies |
| Service authentication | Manual file creation | Package post-install | Creates auth files with proper permissions |
| SSH key generation | Manual openssl | `ssh-keygen` in entrypoint | Standard tool, proper key formats |

**Key insight:** OpenNebula packages handle complex setup during install. Use RUNLEVEL=1 to suppress systemd, but let the package scripts configure directories, permissions, and initial files.

## Common Pitfalls

### Pitfall 1: Scheduler as Persistent Service
**What goes wrong:** Attempting to start opennebula-scheduler as a daemon (worked in 6.10)
**Why it happens:** In 7.0, scheduler is no longer a persistent service - it runs on demand
**How to avoid:** Do NOT try to start scheduler service. oned handles scheduling internally now.
**Warning signs:** Looking for scheduler service file, scheduler not found errors

### Pitfall 2: Missing Authentication Files
**What goes wrong:** Services fail to start with authentication errors
**Why it happens:** Auth files must exist before services start: `/var/lib/one/.one/one_auth`, `oneflow_auth`, `onegate_auth`
**How to avoid:** Create auth files in entrypoint before starting services
**Warning signs:** "Auth file not found", permission denied on auth files

### Pitfall 3: Service Start Order
**What goes wrong:** OneFlow/OneGate fail to connect to oned
**Why it happens:** Services need oned API available before they start
**How to avoid:** Start oned first, wait for port 2633 to be available, then start others
**Warning signs:** Connection refused to localhost:2633

### Pitfall 4: oneadmin User Not Existing
**What goes wrong:** Services fail with user permission errors
**Why it happens:** opennebula-common package creates oneadmin user; if skipped, user doesn't exist
**How to avoid:** Ensure opennebula-common is installed (dependency of opennebula package)
**Warning signs:** "oneadmin user not found", permission denied errors

### Pitfall 5: FireEdge vs Old Sunstone Confusion
**What goes wrong:** Looking for sunstone package or sunstone-server.rb
**Why it happens:** In 7.0, old Ruby Sunstone is removed. FireEdge (Node.js) provides Sunstone
**How to avoid:** Install opennebula-fireedge, access Sunstone at `/fireedge/sunstone`
**Warning signs:** sunstone package not found, looking for Ruby Sunstone files

### Pitfall 6: SQLite File Permissions
**What goes wrong:** oned fails to write to SQLite database
**Why it happens:** Database file needs to be writable by oneadmin
**How to avoid:** Ensure `/var/lib/one/one.db` is owned by oneadmin:oneadmin
**Warning signs:** Database locked, permission denied on one.db

## Code Examples

### Entrypoint Script Pattern
```bash
#!/bin/bash
# Source: User's existing 6.10 pattern + research findings

set -e

# Generate SSH keys if not present
if [ ! -f /var/lib/one/.ssh/id_rsa ]; then
    sudo -u oneadmin ssh-keygen -t rsa -N "" -f /var/lib/one/.ssh/id_rsa
    cat /var/lib/one/.ssh/id_rsa.pub >> /var/lib/one/.ssh/authorized_keys
    chmod 600 /var/lib/one/.ssh/authorized_keys
fi

# Setup oneadmin authentication
ONEADMIN_PASSWORD=${ONEADMIN_PASSWORD:-oneadmin}
echo "oneadmin:${ONEADMIN_PASSWORD}" > /var/lib/one/.one/one_auth
echo "serveradmin:${ONEADMIN_PASSWORD}" > /var/lib/one/.one/oneflow_auth
echo "serveradmin:${ONEADMIN_PASSWORD}" > /var/lib/one/.one/onegate_auth
chown oneadmin:oneadmin /var/lib/one/.one/*_auth
chmod 600 /var/lib/one/.one/*_auth

# Configure database backend
if [ "${DB_BACKEND}" = "mysql" ]; then
    sed -i 's/BACKEND = "sqlite"/BACKEND = "mysql"/' /etc/one/oned.conf
    # Add MySQL configuration...
fi

# Configure service endpoints
sed -i "s|:host:.*|:host: 0.0.0.0|" /etc/one/oneflow-server.conf
sed -i "s|:host:.*|:host: 0.0.0.0|" /etc/one/onegate-server.conf

exec "$@"
```

### Dockerfile Healthcheck Pattern
```dockerfile
# Source: Docker best practices + OpenNebula API research
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD oneuser show 0 > /dev/null 2>&1 || exit 1
```

Alternative using XML-RPC API:
```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -sf http://localhost:2633/RPC2 > /dev/null || exit 1
```

### Database Configuration in oned.conf
```
# SQLite (default - for testing/development)
DB = [ BACKEND = "sqlite",
       TIMEOUT = 2500 ]

# MySQL/MariaDB (for production)
DB = [ BACKEND = "mysql",
       SERVER = "mysql-host",
       PORT = 3306,
       USER = "oneadmin",
       PASSWD = "password",
       DB_NAME = "opennebula",
       CONNECTIONS = 25 ]
```

## State of the Art

| Old Approach (6.10) | Current Approach (7.0) | When Changed | Impact |
|--------------------|------------------------|--------------|--------|
| Ruby Sunstone | FireEdge (Node.js) | 7.0 | Use opennebula-fireedge, access at /fireedge/sunstone |
| Persistent scheduler daemon | On-demand scheduler | 7.0 | No scheduler service to start |
| Labels on resources | Labels in user/group templates | 7.0 | Automatic migration during upgrade |
| vCenter support | Removed | 7.0 | Not relevant for this project |

**Deprecated/outdated:**
- `opennebula-sunstone` package - replaced by `opennebula-fireedge`
- `opennebula-scheduler` as persistent service - now runs on demand
- Wild VM import capability - removed in 7.0

## Open Questions

Things that couldn't be fully resolved:

1. **Guacd requirement for FireEdge**
   - What we know: guacd provides remote console access (VNC/RDP/SSH)
   - What's unclear: Whether FireEdge works without it for basic Sunstone
   - Recommendation: Include opennebula-guacd but don't require it for basic health

2. **SSH Agent for oneadmin**
   - What we know: oned service depends on ssh-agent.env
   - What's unclear: Whether this is needed for control plane without hypervisors
   - Recommendation: Generate SSH keys but skip ssh-agent setup initially

3. **HEM (Hook Execution Manager) service**
   - What we know: Auto-starts with oned in systemd
   - What's unclear: How to start manually, whether required
   - Recommendation: Monitor if hooks fail, investigate HEM if needed

## Sources

### Primary (HIGH confidence)
- OpenNebula 7.0 Official Docs - Repository Setup: https://docs.opennebula.io/7.0/software/installation_process/manual_installation/opennebula_repository_configuration/
- OpenNebula 7.0 Official Docs - Front-end Installation: https://docs.opennebula.io/7.0/software/installation_process/manual_installation/front_end_installation/
- OpenNebula 7.0 Official Docs - Database Setup: https://docs.opennebula.io/7.0/software/installation_process/manual_installation/database/
- OpenNebula 7.0 Official Docs - Compatibility Guide: https://docs.opennebula.io/7.0/software/release_information/release_notes_70/compatibility/
- OpenNebula 7.0 Official Docs - oned Configuration: https://docs.opennebula.io/7.0/product/operation_references/opennebula_services_configuration/oned/
- OpenNebula GitHub - systemd service files: https://github.com/OpenNebula/one/tree/master/share/pkgs/services/systemd
- OpenNebula 7.0 Package Index: https://downloads.opennebula.io/repo/7.0.0/Ubuntu/24.04/pool/opennebula/

### Secondary (MEDIUM confidence)
- User's existing docker_opennebula repo (6.10): https://github.com/pablodelarco/docker_opennebula
- OpenNebula 6.0 Containerized Deployment Reference: https://docs.opennebula.io/6.0/installation_and_configuration/containerized_deployment/reference.html

### Tertiary (LOW confidence)
- Community forum discussions on Docker without systemd
- ospalax/onedocker project (different approach with systemd in podman)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Official packages verified in 7.0 repository
- Architecture: HIGH - Service commands from systemd files, proven RUNLEVEL pattern from user's repo
- Configuration: HIGH - Official documentation for config files and options
- Pitfalls: MEDIUM - Some based on 6.10 to 7.0 compatibility guide, some from general containerization knowledge

**Research date:** 2026-01-23
**Valid until:** ~2026-02-23 (30 days - stable release)

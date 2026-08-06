#!/bin/bash
set -e

# ============================================================================
# OpenNebula Control Plane Entrypoint Script
# Configures authentication, database, and service endpoints at runtime
# ============================================================================

# ----------------------------------------------------------------------------
# Ensure required directories exist (for fresh PV mounts)
# ----------------------------------------------------------------------------
mkdir -p /var/lib/one/.ssh /var/lib/one/.one
chown oneadmin:oneadmin /var/lib/one/.ssh /var/lib/one/.one
chmod 700 /var/lib/one/.ssh

# Restore remotes directory if it doesn't exist (PV mount overwrites it)
if [ ! -d /var/lib/one/remotes ]; then
    echo "Restoring remotes directory from preserved copy..."
    cp -a /usr/share/one/remotes-dist /var/lib/one/remotes
    chown -R oneadmin:oneadmin /var/lib/one/remotes
fi

# ----------------------------------------------------------------------------
# SSH Key Generation for oneadmin
# ----------------------------------------------------------------------------
if [ ! -f /var/lib/one/.ssh/id_rsa ]; then
    echo "Generating SSH keys for oneadmin..."
    sudo -u oneadmin ssh-keygen -t rsa -N "" -f /var/lib/one/.ssh/id_rsa
    cat /var/lib/one/.ssh/id_rsa.pub >> /var/lib/one/.ssh/authorized_keys
    chown oneadmin:oneadmin /var/lib/one/.ssh/authorized_keys
    chmod 600 /var/lib/one/.ssh/authorized_keys
fi

# ----------------------------------------------------------------------------
# Authentication Files Setup
# ----------------------------------------------------------------------------
ONEADMIN_PASSWORD="${ONEADMIN_PASSWORD:-oneadmin}"
DB_BACKEND="${DB_BACKEND:-sqlite}"

# Always remove sunstone_auth on container start
# oned creates this file during bootstrap, but if oned crashes mid-bootstrap,
# the file exists but database is incomplete. oned will error if it sees
# sunstone_auth but needs to bootstrap. Deleting it ensures clean startup.
# oned will recreate it automatically.
rm -f /var/lib/one/.one/sunstone_auth

# Check if this is a fresh installation (no one_key = never bootstrapped)
FRESH_INSTALL="no"
if [ ! -f /var/lib/one/.one/one_key ]; then
    echo "Fresh installation - preparing for clean bootstrap..."
    FRESH_INSTALL="yes"
    # Remove SQLite database if present (MySQL databases are external)
    rm -f /var/lib/one/one.db
    # Remove oned-generated auth files - will be recreated during bootstrap
    rm -f /var/lib/one/.one/one_key
    rm -f /var/lib/one/.one/fireedge_key
    rm -f /var/lib/one/.one/oneflow_auth
    rm -f /var/lib/one/.one/onegate_auth

    # Create one_auth with our password BEFORE bootstrap
    # oned will use this password for the oneadmin user during bootstrap
    echo "oneadmin:${ONEADMIN_PASSWORD}" > /var/lib/one/.one/one_auth
    chown oneadmin:oneadmin /var/lib/one/.one/one_auth
    chmod 600 /var/lib/one/.one/one_auth
else
    echo "Existing installation detected (one_key exists)"
    # Ensure one_auth exists (may have been deleted manually)
    if [ ! -f /var/lib/one/.one/one_auth ]; then
        echo "Restoring one_auth file..."
        echo "oneadmin:${ONEADMIN_PASSWORD}" > /var/lib/one/.one/one_auth
        chown oneadmin:oneadmin /var/lib/one/.one/one_auth
        chmod 600 /var/lib/one/.one/one_auth
    fi
fi

# Export ONE_AUTH for CLI tools
export ONE_AUTH=/var/lib/one/.one/one_auth

# Create service auth files if they don't exist.
# IMPORTANT: skip this on a fresh installation. oned generates these files
# itself during bootstrap and refuses to bootstrap when they already exist
# ("Password file ... already exists but OpenNebula is boostraping the
# database"), which leaves oned crash-looping with exit status 255.
if [ "$FRESH_INSTALL" = "yes" ]; then
    echo "Fresh install: leaving service auth files to oned bootstrap"
    rm -f /var/lib/one/.one/oneflow_auth \
          /var/lib/one/.one/onegate_auth \
          /var/lib/one/.one/sunstone_auth
fi

if [ "$FRESH_INSTALL" != "yes" ] && [ ! -f /var/lib/one/.one/oneflow_auth ]; then
    echo "Creating OneFlow auth file..."
    echo "serveradmin:${ONEADMIN_PASSWORD}" > /var/lib/one/.one/oneflow_auth
    chown oneadmin:oneadmin /var/lib/one/.one/oneflow_auth
    chmod 600 /var/lib/one/.one/oneflow_auth
fi

if [ "$FRESH_INSTALL" != "yes" ] && [ ! -f /var/lib/one/.one/onegate_auth ]; then
    echo "Creating OneGate auth file..."
    echo "serveradmin:${ONEADMIN_PASSWORD}" > /var/lib/one/.one/onegate_auth
    chown oneadmin:oneadmin /var/lib/one/.one/onegate_auth
    chmod 600 /var/lib/one/.one/onegate_auth
fi

# Note: sunstone_auth is created by oned during bootstrap
# We don't create it here as oned will create it with the proper serveradmin token


# ----------------------------------------------------------------------------
# Seed /var/lib/one from the image skeleton
# ----------------------------------------------------------------------------
# /var/lib/one is a mount point for the persistent volume, so anything the
# packages installed there (oneks controlplane families, oneform providers,
# driver remotes...) is hidden the moment the volume is mounted. The image
# keeps a pristine copy at /usr/share/one/one-skel; copy over only what is
# missing, never overwriting existing state.
if [ -d /usr/share/one/one-skel ]; then
    echo "Seeding /var/lib/one from image skeleton (missing entries only)..."
    cp -a -n /usr/share/one/one-skel/. /var/lib/one/ 2>/dev/null || true
    chown -R oneadmin:oneadmin /var/lib/one
fi

# ----------------------------------------------------------------------------
# Database Configuration
# ----------------------------------------------------------------------------
# DB_BACKEND already set above during bootstrap check

if [ "$DB_BACKEND" = "mysql" ]; then
    echo "Configuring MySQL database backend..."

    # Wait for the database to accept connections before starting oned.
    # oned exits with status 255 when the DB is unreachable and supervisord
    # respawns it forever, which surfaces as an unexplained crash loop. Fail
    # fast and loud instead. Also absorbs slow DB startup and sidecar races.
    echo "Waiting for MySQL at ${DB_HOST}:${DB_PORT} ..."
    DB_WAIT_TIMEOUT="${DB_WAIT_TIMEOUT:-120}"
    _waited=0
    until mysqladmin ping -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" --silent 2>/dev/null; do
        if [ "$_waited" -ge "$DB_WAIT_TIMEOUT" ]; then
            echo "FATAL: cannot reach MySQL at ${DB_HOST}:${DB_PORT} after ${DB_WAIT_TIMEOUT}s" >&2
            echo "FATAL: check DB_HOST, DB_PORT, credentials, DNS and network policy" >&2
            exit 1
        fi
        sleep 3; _waited=$((_waited+3))
        echo "  still waiting for MySQL (${_waited}s/${DB_WAIT_TIMEOUT}s)"
    done
    echo "MySQL is reachable"

    # Variables already set above during bootstrap check
    if [ -z "$DB_PASSWORD" ]; then
        echo "WARNING: DB_PASSWORD not set for MySQL backend"
    fi

    # Replace the entire DB block with complete MySQL configuration
    # The default oned.conf only has BACKEND and TIMEOUT, we need to add all MySQL params
    sed -i '/^DB = \[/,/\]/{
        /^DB = \[/c\
DB = [ BACKEND = "mysql",\
       SERVER = "'"${DB_HOST}"'",\
       PORT = '"${DB_PORT}"',\
       USER = "'"${DB_USER}"'",\
       PASSWD = "'"${DB_PASSWORD}"'",\
       DB_NAME = "'"${DB_NAME}"'",\
       CONNECTIONS = 25,\
       COMPARE_BINARY = "no" ]
        d
    }' /etc/one/oned.conf
fi

# ----------------------------------------------------------------------------
# Database Schema Upgrade
# ----------------------------------------------------------------------------
# When the image version moves past the deployed database schema, oned
# refuses to start until 'onedb upgrade' runs. For existing installations,
# attempt the upgrade automatically with a backup on the persistent volume.
# onedb reads the DB connection settings from oned.conf (configured above)
# and is a no-op when the schema is already current. On failure, warn and
# continue: oned logs the exact schema mismatch itself, and the backup
# allows a manual restore.
if [ -f /var/lib/one/.one/one_key ]; then
    BACKUP_DIR=/var/lib/one/backups/db
    mkdir -p "$BACKUP_DIR"
    chown -R oneadmin:oneadmin "$BACKUP_DIR"
    echo "Checking database schema version (onedb upgrade)..."
    if ! sudo -u oneadmin onedb upgrade --backup "$BACKUP_DIR/onedb-$(date +%Y%m%d-%H%M%S).sql"; then
        echo "WARNING: automatic 'onedb upgrade' failed. If oned refuses to start"
        echo "with a database version mismatch, run 'onedb upgrade' manually in"
        echo "this container. Backups (if created) are in $BACKUP_DIR."
    fi
fi

# ----------------------------------------------------------------------------
# Scheduler
# ----------------------------------------------------------------------------
# The scheduler MUST stay enabled. This image is a front-end that manages
# REMOTE hypervisor nodes, and without one_sched every VM stays PENDING
# forever because nothing ever places it on a host. Verified working in the
# container: "one_sched.rb -t 15 -p rank -o one_drs".
echo "Scheduler: enabled (required to place VMs on remote hosts)"

# ----------------------------------------------------------------------------
# Service Endpoint Configuration
# Configure services to listen on 0.0.0.0 for container networking
# ----------------------------------------------------------------------------

# Configure OneFlow to listen on all interfaces
if [ -f /etc/one/oneflow-server.conf ]; then
    sed -i 's/:host:.*/:host: 0.0.0.0/' /etc/one/oneflow-server.conf
fi

# Configure OneGate to listen on all interfaces
if [ -f /etc/one/onegate-server.conf ]; then
    sed -i 's/:host:.*/:host: 0.0.0.0/' /etc/one/onegate-server.conf
fi

# ----------------------------------------------------------------------------
# HOSTNAME Configuration for Driver Operations
# ----------------------------------------------------------------------------
# HOSTNAME tells oned what address to advertise to hypervisors for driver operations.
# Auto-detection often fails in containers, returning internal pod IPs.
# Set OPENNEBULA_HOSTNAME to a stable, resolvable address.
OPENNEBULA_HOSTNAME="${OPENNEBULA_HOSTNAME:-}"

if [ -n "$OPENNEBULA_HOSTNAME" ] && [ "$OPENNEBULA_HOSTNAME" != "auto" ]; then
    echo "Setting explicit HOSTNAME in oned.conf: $OPENNEBULA_HOSTNAME"
    # Check if HOSTNAME line exists (commented or not) and update it
    if grep -q "^#*\s*HOSTNAME\s*=" /etc/one/oned.conf; then
        sed -i 's/^#*\s*HOSTNAME\s*=.*/HOSTNAME = "'"${OPENNEBULA_HOSTNAME}"'"/' /etc/one/oned.conf
    else
        # Add HOSTNAME if not present
        echo "HOSTNAME = \"${OPENNEBULA_HOSTNAME}\"" >> /etc/one/oned.conf
    fi
fi

# ----------------------------------------------------------------------------
# MONITOR_ADDRESS Configuration for Monitoring Probes
# ----------------------------------------------------------------------------
# MONITOR_ADDRESS tells hypervisors where to send monitoring data.
# Default "auto" may resolve to wrong address in containerized deployments.
OPENNEBULA_MONITOR_ADDRESS="${OPENNEBULA_MONITOR_ADDRESS:-}"

if [ -n "$OPENNEBULA_MONITOR_ADDRESS" ] && [ "$OPENNEBULA_MONITOR_ADDRESS" != "auto" ]; then
    echo "Setting explicit MONITOR_ADDRESS in monitord.conf: $OPENNEBULA_MONITOR_ADDRESS"
    # Update MONITOR_ADDRESS in the NETWORK section of monitord.conf
    if [ -f /etc/one/monitord.conf ]; then
        sed -i 's/MONITOR_ADDRESS\s*=\s*"[^"]*"/MONITOR_ADDRESS = "'"${OPENNEBULA_MONITOR_ADDRESS}"'"/' /etc/one/monitord.conf
    fi
fi

# ----------------------------------------------------------------------------
# Ensure proper ownership of runtime directories
# ----------------------------------------------------------------------------
# Pre-create log files with correct ownership before supervisord starts
# This prevents supervisord from creating them as root
touch /var/log/one/oned.log /var/log/one/oned.error
touch /var/log/one/fireedge.log /var/log/one/fireedge.error
touch /var/log/one/oneflow.log /var/log/one/oneflow.error
touch /var/log/one/onegate.log /var/log/one/onegate.error
chown -R oneadmin:oneadmin /var/log/one

# Ensure database file is writable by oneadmin (sqlite mode)
if [ -f /var/lib/one/one.db ]; then
    chown oneadmin:oneadmin /var/lib/one/one.db
fi

# Ensure all of /var/lib/one is owned by oneadmin
chown -R oneadmin:oneadmin /var/lib/one

# ----------------------------------------------------------------------------
# Container logging
# ----------------------------------------------------------------------------
# Send oned output to stdout so Kubernetes and Docker capture it. Without this
# oned writes to /var/log/one/oned.log inside the container and the real error
# never reaches "kubectl logs", leaving only supervisord lifecycle noise.
sed -i 's/SYSTEM *= *"file"/SYSTEM = "std"/' /etc/one/oned.conf
echo "Logging: oned writes to stdout (LOG SYSTEM=std)"


# ----------------------------------------------------------------------------
# Keep OneForm and OneKS current
# ----------------------------------------------------------------------------
# OneForm/OneKS carry exact-version dependencies on the OpenNebula core
# (Depends: opennebula (= X.Y.Z-1)), so they cannot move independently. This
# only picks up patch releases inside the series the image was built from.
# It never crosses to a new series and never fails the container: if the
# repository is unreachable, the baked-in versions are kept.
if [ "${AUTO_UPDATE_ADDONS:-yes}" = "yes" ]; then
    echo "Addons: checking for OneForm/OneKS updates..."
    if timeout 60 apt-get update -qq >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive timeout 300 apt-get install -y --only-upgrade \
            -o Dpkg::Options::=--force-confold \
            opennebula-form opennebula-ks >/dev/null 2>&1 \
            || echo "Addons: WARN update failed, keeping the image versions"
    else
        echo "Addons: WARN package repository unreachable, keeping the image versions"
    fi
fi
echo "Addons: OneForm $(dpkg-query -W -f='${Version}' opennebula-form 2>/dev/null || echo absent), OneKS $(dpkg-query -W -f='${Version}' opennebula-ks 2>/dev/null || echo absent)"

# OneKS server must listen on all interfaces inside the container
if [ -f /etc/one/oneks-server.conf ]; then
    sed -i 's/^\( *\):bind: 127.0.0.1/\1:bind: 0.0.0.0/' /etc/one/oneks-server.conf
fi


# ----------------------------------------------------------------------------
# TPROXY (required by OneKS)
# ----------------------------------------------------------------------------
# OneKS refuses to start unless TPROXY is configured: its cluster router uses
# the link-local address 169.254.16.9 so guest VMs can reach OneGate and the
# XML-RPC endpoint without a routable path to the front-end. Point it at the
# address this front-end advertises to hypervisors.
NETCONF=/var/lib/one/remotes/etc/vnm/OpenNebulaNetwork.conf
if [ -f "$NETCONF" ] && ! grep -qE "^:tproxy:" "$NETCONF"; then
    TPROXY_ADDR="${OPENNEBULA_MONITOR_ADDRESS:-${OPENNEBULA_HOSTNAME:-$(hostname -f)}}"
    echo "TPROXY: enabling for OneKS, remote_addr=${TPROXY_ADDR}"
    cat >> "$NETCONF" <<EOF

:tproxy:
- :service_port: 5030
  :remote_addr: ${TPROXY_ADDR}
  :remote_port: 5030
- :service_port: 2633
  :remote_addr: ${TPROXY_ADDR}
  :remote_port: 2633
EOF
    chown oneadmin:oneadmin "$NETCONF"
fi

# ----------------------------------------------------------------------------
# Execute CMD
# ----------------------------------------------------------------------------
exec "$@"

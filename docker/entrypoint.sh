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

# Check if oned has already bootstrapped (user_pool should have at least oneadmin)
# The package creates an empty schema, but oned creates actual user data on first run
DB_BOOTSTRAPPED=$(sqlite3 /var/lib/one/one.db "SELECT COUNT(*) FROM user_pool;" 2>/dev/null || echo "0")

if [ "$DB_BOOTSTRAPPED" = "0" ]; then
    echo "Fresh database - removing package files for clean bootstrap..."
    # Remove database so oned can create it fresh with correct schema and data
    rm -f /var/lib/one/one.db
    # Remove ALL auth files - oned will recreate the internal ones during bootstrap
    rm -f /var/lib/one/.one/sunstone_auth
    rm -f /var/lib/one/.one/one_key
    rm -f /var/lib/one/.one/fireedge_key
    rm -f /var/lib/one/.one/one_auth
    rm -f /var/lib/one/.one/oneflow_auth
    rm -f /var/lib/one/.one/onegate_auth

    # Create one_auth with our password BEFORE bootstrap
    # oned will use this password for the oneadmin user during bootstrap
    echo "oneadmin:${ONEADMIN_PASSWORD}" > /var/lib/one/.one/one_auth
    chown oneadmin:oneadmin /var/lib/one/.one/one_auth
    chmod 600 /var/lib/one/.one/one_auth
fi

# Export ONE_AUTH for CLI tools
export ONE_AUTH=/var/lib/one/.one/one_auth

# Create service auth files if they don't exist
# OneFlow and OneGate use the same credentials as oneadmin
if [ ! -f /var/lib/one/.one/oneflow_auth ]; then
    echo "Creating OneFlow auth file..."
    echo "serveradmin:${ONEADMIN_PASSWORD}" > /var/lib/one/.one/oneflow_auth
    chown oneadmin:oneadmin /var/lib/one/.one/oneflow_auth
    chmod 600 /var/lib/one/.one/oneflow_auth
fi

if [ ! -f /var/lib/one/.one/onegate_auth ]; then
    echo "Creating OneGate auth file..."
    echo "serveradmin:${ONEADMIN_PASSWORD}" > /var/lib/one/.one/onegate_auth
    chown oneadmin:oneadmin /var/lib/one/.one/onegate_auth
    chmod 600 /var/lib/one/.one/onegate_auth
fi

# ----------------------------------------------------------------------------
# Database Configuration
# ----------------------------------------------------------------------------
DB_BACKEND="${DB_BACKEND:-sqlite}"

if [ "$DB_BACKEND" = "mysql" ]; then
    echo "Configuring MySQL database backend..."

    DB_HOST="${DB_HOST:-localhost}"
    DB_PORT="${DB_PORT:-3306}"
    DB_USER="${DB_USER:-oneadmin}"
    DB_NAME="${DB_NAME:-opennebula}"

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
# Disable Scheduler (not needed in Kubernetes control-plane-only mode)
# The "rank" scheduler module is not available in the base package
# ----------------------------------------------------------------------------
sed -i '/^SCHED_MAD = \[/,/^\]/{s/^/#/}' /etc/one/oned.conf

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
# Execute CMD
# ----------------------------------------------------------------------------
exec "$@"

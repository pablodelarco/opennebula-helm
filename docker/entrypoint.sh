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
# SSH Key Setup for oneadmin
# ----------------------------------------------------------------------------
if [ ! -f /var/lib/one/.ssh/id_rsa ]; then
    # Check if SSH keys are mounted from secret
    if [ -f /var/lib/one/.ssh-secret/id_rsa ]; then
        echo "Using mounted SSH keys from secret..."
        cp /var/lib/one/.ssh-secret/id_rsa /var/lib/one/.ssh/id_rsa
        cp /var/lib/one/.ssh-secret/id_rsa.pub /var/lib/one/.ssh/id_rsa.pub
        chown oneadmin:oneadmin /var/lib/one/.ssh/id_rsa /var/lib/one/.ssh/id_rsa.pub
        chmod 600 /var/lib/one/.ssh/id_rsa
        chmod 644 /var/lib/one/.ssh/id_rsa.pub
    else
        echo "Generating SSH keys for oneadmin..."
        sudo -u oneadmin ssh-keygen -t rsa -N "" -f /var/lib/one/.ssh/id_rsa
    fi
    cat /var/lib/one/.ssh/id_rsa.pub >> /var/lib/one/.ssh/authorized_keys
    chown oneadmin:oneadmin /var/lib/one/.ssh/authorized_keys
    chmod 600 /var/lib/one/.ssh/authorized_keys
fi

# Configure SSH to accept new host keys automatically
# This allows oned to connect to newly provisioned hypervisors without manual ssh-keyscan
cat > /var/lib/one/.ssh/config << 'EOF'
Host *
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.ssh/known_hosts
EOF
chown oneadmin:oneadmin /var/lib/one/.ssh/config
chmod 600 /var/lib/one/.ssh/config

# ----------------------------------------------------------------------------
# Authentication Files Setup
# ----------------------------------------------------------------------------
ONEADMIN_PASSWORD="${ONEADMIN_PASSWORD:-oneadmin}"

# Check if oned has already bootstrapped (user_pool should have at least oneadmin)
# The package creates an empty schema, but oned creates actual user data on first run
if [ "$DB_BACKEND" = "mysql" ]; then
    # For MySQL, check if user_pool has data
    # Use timeout and retries in case DB is still starting
    for i in 1 2 3 4 5; do
        DB_BOOTSTRAPPED=$(mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
            -sN -e "SELECT COUNT(*) FROM user_pool;" 2>/dev/null || echo "0")
        [ "$DB_BOOTSTRAPPED" != "0" ] && break
        echo "Waiting for database... attempt $i/5"
        sleep 2
    done
else
    # For SQLite, check local database
    DB_BOOTSTRAPPED=$(sqlite3 /var/lib/one/one.db "SELECT COUNT(*) FROM user_pool;" 2>/dev/null || echo "0")
fi

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

# Note: OneFlow and OneGate auth files are created by oned during bootstrap
# Do not create them here to avoid interfering with bootstrap

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
# Enable Scheduler for VM placement
# The scheduler assigns VMs to hosts based on capacity and policies
# ----------------------------------------------------------------------------
# Uncomment SCHED_MAD if it's commented (default config has it commented)
sed -i '/^#SCHED_MAD = \[/,/^#\]/{s/^#//}' /etc/one/oned.conf

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
# Exclude .ssh-secret which is a read-only mounted secret
find /var/lib/one -path /var/lib/one/.ssh-secret -prune -o -exec chown oneadmin:oneadmin {} + 2>/dev/null || true

# ----------------------------------------------------------------------------
# Execute CMD
# ----------------------------------------------------------------------------
exec "$@"

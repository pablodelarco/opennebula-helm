#!/bin/bash
set -e

# ============================================================================
# OpenNebula Control Plane Entrypoint Script
# Configures authentication, database, and service endpoints at runtime
# ============================================================================

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

    # Update oned.conf for MySQL
    sed -i 's/^DB\s*=\s*\[/DB = [/' /etc/one/oned.conf
    sed -i 's/BACKEND\s*=\s*"sqlite"/BACKEND = "mysql"/' /etc/one/oned.conf
    sed -i "s/SERVER\s*=\s*\"[^\"]*\"/SERVER = \"${DB_HOST}\"/" /etc/one/oned.conf
    sed -i "s/PORT\s*=\s*[0-9]*/PORT = ${DB_PORT}/" /etc/one/oned.conf
    sed -i "s/USER\s*=\s*\"[^\"]*\"/USER = \"${DB_USER}\"/" /etc/one/oned.conf
    sed -i "s/PASSWD\s*=\s*\"[^\"]*\"/PASSWD = \"${DB_PASSWORD}\"/" /etc/one/oned.conf
    sed -i "s/DB_NAME\s*=\s*\"[^\"]*\"/DB_NAME = \"${DB_NAME}\"/" /etc/one/oned.conf
fi

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
chown -R oneadmin:oneadmin /var/lib/one

# ----------------------------------------------------------------------------
# Execute CMD
# ----------------------------------------------------------------------------
exec "$@"

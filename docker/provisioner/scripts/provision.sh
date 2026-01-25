#!/bin/bash
# OpenNebula Host Provisioner Script
# This script waits for the OpenNebula front-end to be ready,
# then runs Ansible to provision hypervisor nodes.

set -e

# Configuration from environment
FRONTEND_HOST="${FRONTEND_HOST:-opennebula}"
FRONTEND_PORT="${FRONTEND_PORT:-2633}"
INVENTORY_FILE="${INVENTORY_FILE:-/config/inventory.yml}"
ONEADMIN_PUBKEY_FILE="${ONEADMIN_PUBKEY_FILE:-/secrets/id_rsa.pub}"
MAX_RETRIES="${MAX_RETRIES:-60}"
RETRY_INTERVAL="${RETRY_INTERVAL:-10}"

echo "========================================"
echo "OpenNebula Host Provisioner"
echo "========================================"
echo "Frontend: ${FRONTEND_HOST}:${FRONTEND_PORT}"
echo "Inventory: ${INVENTORY_FILE}"
echo ""

# Check required files
if [ ! -f "${INVENTORY_FILE}" ]; then
    echo "ERROR: Inventory file not found: ${INVENTORY_FILE}"
    exit 1
fi

if [ ! -f "${ONEADMIN_PUBKEY_FILE}" ]; then
    echo "ERROR: Public key file not found: ${ONEADMIN_PUBKEY_FILE}"
    exit 1
fi

# Export public key for Ansible
export ONEADMIN_PUBKEY=$(cat "${ONEADMIN_PUBKEY_FILE}")
echo "Loaded oneadmin public key"

# Wait for OpenNebula API to be ready
echo ""
echo "Waiting for OpenNebula API to be ready..."
retry_count=0
while [ $retry_count -lt $MAX_RETRIES ]; do
    if curl -s "http://${FRONTEND_HOST}:${FRONTEND_PORT}/RPC2" > /dev/null 2>&1; then
        echo "OpenNebula API is ready!"
        break
    fi
    retry_count=$((retry_count + 1))
    echo "  Attempt ${retry_count}/${MAX_RETRIES} - waiting ${RETRY_INTERVAL}s..."
    sleep $RETRY_INTERVAL
done

if [ $retry_count -ge $MAX_RETRIES ]; then
    echo "ERROR: OpenNebula API did not become ready in time"
    exit 1
fi

# Additional wait for services to stabilize
echo "Waiting 10s for services to stabilize..."
sleep 10

# Run Ansible playbook
echo ""
echo "========================================"
echo "Running Ansible Provisioner"
echo "========================================"
echo ""

ansible-playbook \
    -i "${INVENTORY_FILE}" \
    /ansible/playbook.yml \
    -e "frontend_host=${FRONTEND_HOST}" \
    -e "frontend_port=${FRONTEND_PORT}" \
    -e "oneadmin_pubkey='${ONEADMIN_PUBKEY}'" \
    -v

echo ""
echo "========================================"
echo "Provisioning Complete!"
echo "========================================"

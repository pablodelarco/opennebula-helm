#!/bin/bash
# OpenNebula Helm Chart Installer with Progress Output
set -e

RELEASE_NAME="${1:-opennebula}"
VALUES_FILE="${2:-}"
NAMESPACE="${NAMESPACE:-default}"
TIMEOUT="${TIMEOUT:-600}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "OpenNebula Helm Chart Installation"
echo "=========================================="
echo "Release: ${RELEASE_NAME}"
echo "Namespace: ${NAMESPACE}"
echo ""

# Build helm command
HELM_CMD="helm install ${RELEASE_NAME} ./charts/opennebula"
if [ -n "${VALUES_FILE}" ]; then
    HELM_CMD="${HELM_CMD} -f ${VALUES_FILE}"
fi
HELM_CMD="${HELM_CMD} -n ${NAMESPACE}"

# Track timing
TOTAL_START=$(date +%s)

# Step 1: Helm install (now fast - no blocking hooks)
echo -n "[1/5] Installing Helm chart... "
START=$(date +%s)
${HELM_CMD} > /dev/null 2>&1
END=$(date +%s)
echo -e "${GREEN}✓${NC} ($((END - START))s)"

# Step 2: SSH key generation
echo -n "[2/5] Generating SSH keys... "
START=$(date +%s)
while ! kubectl get secret ${RELEASE_NAME}-ssh-generated -n ${NAMESPACE} &>/dev/null; do
    sleep 1
done
END=$(date +%s)
echo -e "${GREEN}✓${NC} ($((END - START))s)"

# Step 3: MariaDB
echo -n "[3/5] Starting MariaDB... "
START=$(date +%s)
kubectl wait --for=condition=ready pod/${RELEASE_NAME}-mariadb-0 -n ${NAMESPACE} --timeout=${TIMEOUT}s > /dev/null 2>&1
END=$(date +%s)
echo -e "${GREEN}✓${NC} ($((END - START))s)"

# Step 4: OpenNebula frontend
echo -n "[4/5] Starting OpenNebula frontend... "
START=$(date +%s)
kubectl wait --for=condition=ready pod/${RELEASE_NAME}-0 -n ${NAMESPACE} --timeout=${TIMEOUT}s > /dev/null 2>&1
END=$(date +%s)
echo -e "${GREEN}✓${NC} ($((END - START))s)"

TOTAL_END=$(date +%s)
CORE_TIME=$((TOTAL_END - TOTAL_START))

echo ""
echo -e "${GREEN}=========================================="
echo "Core Installation Complete! (${CORE_TIME}s)"
echo -e "==========================================${NC}"
echo ""
echo "Access UI: kubectl port-forward svc/${RELEASE_NAME} 8080:2616"
echo "           http://localhost:8080/fireedge/sunstone"
echo ""

# Step 5: Host provisioner (runs in background)
if kubectl get job ${RELEASE_NAME}-host-provisioner -n ${NAMESPACE} &>/dev/null; then
    echo -e "${BLUE}[5/5] Host provisioner running in background...${NC}"
    echo "     ─────────────────────────────────────"

    # Wait for provisioner pod to exist
    while true; do
        POD=$(kubectl get pods -n ${NAMESPACE} -l job-name=${RELEASE_NAME}-host-provisioner -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$POD" ]; then
            break
        fi
        sleep 1
    done

    # Wait for pod to be running
    while true; do
        PHASE=$(kubectl get pod $POD -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$PHASE" = "Running" ] || [ "$PHASE" = "Succeeded" ]; then
            break
        fi
        sleep 1
    done

    # Stream logs
    START=$(date +%s)
    kubectl logs -f $POD -n ${NAMESPACE} 2>/dev/null || true
    END=$(date +%s)
    echo "     ─────────────────────────────────────"

    # Check final status
    STATUS=$(kubectl get job ${RELEASE_NAME}-host-provisioner -n ${NAMESPACE} -o jsonpath='{.status.conditions[0].type}' 2>/dev/null)
    if [ "$STATUS" = "Complete" ]; then
        echo -e "     ${GREEN}✓ Provisioner completed ($((END - START))s)${NC}"
    else
        echo -e "     ${YELLOW}⚠ Provisioner status: ${STATUS}${NC}"
    fi

    echo ""
    echo "Hosts:"
    kubectl exec ${RELEASE_NAME}-0 -n ${NAMESPACE} -c opennebula -- onehost list 2>/dev/null || echo "  (pending)"
    echo ""
    echo "Networks:"
    kubectl exec ${RELEASE_NAME}-0 -n ${NAMESPACE} -c opennebula -- onevnet list 2>/dev/null || echo "  (pending)"
fi

TOTAL_END=$(date +%s)
echo ""
echo "=========================================="
echo -e "Total time: $((TOTAL_END - TOTAL_START))s (core: ${CORE_TIME}s)"
echo "=========================================="

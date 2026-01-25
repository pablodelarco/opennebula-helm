#!/bin/bash
# OpenNebula Helm Chart Installer with Progress Output
set -e

RELEASE_NAME="${1:-opennebula}"
VALUES_FILE="${2:-}"
NAMESPACE="${NAMESPACE:-default}"
TIMEOUT="${TIMEOUT:-600}"

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

echo "[1/5] Installing Helm chart (without waiting)..."
${HELM_CMD} 2>&1 | grep -v "^$"

echo ""
echo "[2/5] Waiting for SSH key generation..."
while ! kubectl get secret ${RELEASE_NAME}-ssh-generated -n ${NAMESPACE} &>/dev/null; do
    sleep 2
    echo -n "."
done
echo " Done!"

echo ""
echo "[3/5] Waiting for MariaDB..."
kubectl wait --for=condition=ready pod/${RELEASE_NAME}-mariadb-0 -n ${NAMESPACE} --timeout=${TIMEOUT}s 2>/dev/null || true

echo ""
echo "[4/5] Waiting for OpenNebula frontend..."
kubectl wait --for=condition=ready pod/${RELEASE_NAME}-0 -n ${NAMESPACE} --timeout=${TIMEOUT}s

echo ""
echo "[5/5] Waiting for host provisioner..."
echo "     (Streaming provisioner logs)"
echo "     ---------------------------------"

# Wait for provisioner job to start
while ! kubectl get job ${RELEASE_NAME}-host-provisioner -n ${NAMESPACE} &>/dev/null; do
    sleep 2
done

# Stream logs until job completes
kubectl logs -f job/${RELEASE_NAME}-host-provisioner -n ${NAMESPACE} 2>/dev/null &
LOG_PID=$!

# Wait for job to complete
while true; do
    STATUS=$(kubectl get job ${RELEASE_NAME}-host-provisioner -n ${NAMESPACE} -o jsonpath='{.status.conditions[0].type}' 2>/dev/null)
    if [ "$STATUS" = "Complete" ]; then
        kill $LOG_PID 2>/dev/null || true
        echo ""
        echo "     ---------------------------------"
        echo "     Provisioner completed successfully!"
        break
    elif [ "$STATUS" = "Failed" ]; then
        kill $LOG_PID 2>/dev/null || true
        echo ""
        echo "     ---------------------------------"
        echo "     ERROR: Provisioner failed!"
        exit 1
    fi
    sleep 3
done

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
kubectl exec ${RELEASE_NAME}-0 -n ${NAMESPACE} -c opennebula -- onehost list 2>/dev/null || true
echo ""
echo "Access UI: kubectl port-forward svc/${RELEASE_NAME} 8080:2616"
echo "           http://localhost:8080/fireedge/sunstone"

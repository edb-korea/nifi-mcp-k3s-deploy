#!/usr/bin/env bash
# Remove the NiFi + MCP deployment.
#
#   KUBECTL="sudo k3s kubectl" ./scripts/uninstall.sh           # keep data (PVC) and Secret
#   KUBECTL="sudo k3s kubectl" ./scripts/uninstall.sh --purge   # delete the namespace and ALL data
set -euo pipefail

KUBECTL="${KUBECTL:-kubectl}"
NAMESPACE="nifi"

if [ "${1:-}" = "--purge" ]; then
  echo "This deletes namespace '${NAMESPACE}' including the NiFi data volume. It cannot be undone."
  read -r -p "Type the namespace name to confirm: " answer
  [ "${answer}" = "${NAMESPACE}" ] || { echo "Aborted."; exit 1; }
  ${KUBECTL} delete namespace "${NAMESPACE}"
else
  ${KUBECTL} -n "${NAMESPACE}" delete deployment/nifi service/nifi service/nifi-mcp --ignore-not-found
  echo "Deployment removed. Data (PVC nifi-data) and the Secret were kept; use --purge to delete them."
fi

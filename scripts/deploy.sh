#!/usr/bin/env bash
# Create the namespace and credentials Secret, apply the manifest and wait until NiFi is ready.
# Run it where kubectl can reach the cluster - normally on the k3s VM itself:
#
#   KUBECTL="sudo k3s kubectl" ./scripts/deploy.sh
#
# The NiFi password is read from $NIFI_PASSWORD or asked for interactively (not echoed).
# NiFi single-user mode requires at least 12 characters. Re-running updates the Secret and
# the manifest; restart the Pod afterwards if you changed the password (see README).
set -euo pipefail
cd "$(dirname "$0")/.."

KUBECTL="${KUBECTL:-kubectl}"
NAMESPACE="nifi"
USERNAME="${NIFI_USERNAME:-admin}"
MCP_IMAGE="${MCP_IMAGE:-nifipilot-plus:0.1.0}"
TIMEOUT="${ROLLOUT_TIMEOUT:-15m}"

if [ -z "${NIFI_PASSWORD:-}" ]; then
  read -r -s -p "NiFi password for '${USERNAME}' (min 12 chars): " NIFI_PASSWORD
  echo
fi
if [ "${#NIFI_PASSWORD}" -lt 12 ]; then
  echo "NiFi requires a password of at least 12 characters." >&2
  exit 1
fi

# The image must already exist in k3s' containerd (scripts/push-image.sh), otherwise the
# sidecar ends up in ErrImagePull. Skipped when k3s is not local.
if command -v k3s >/dev/null 2>&1; then
  if ! sudo k3s ctr images ls -q 2>/dev/null | grep -q "${MCP_IMAGE}"; then
    echo "WARNING: image ${MCP_IMAGE} is not imported into k3s yet (run scripts/push-image.sh)." >&2
  fi
fi

echo ">> namespace + credentials Secret"
${KUBECTL} create namespace "${NAMESPACE}" --dry-run=client -o yaml | ${KUBECTL} apply -f -
env_file="$(mktemp)"
trap 'rm -f "${env_file}"' EXIT
chmod 600 "${env_file}"
printf 'username=%s\npassword=%s\n' "${USERNAME}" "${NIFI_PASSWORD}" > "${env_file}"
${KUBECTL} -n "${NAMESPACE}" create secret generic nifi-credentials \
  --from-env-file="${env_file}" --dry-run=client -o yaml | ${KUBECTL} apply -f -

echo ">> applying manifests (sidecar image: ${MCP_IMAGE})"
sed "s|image: nifipilot-plus:0.1.0|image: ${MCP_IMAGE}|" manifests/nifi-with-mcp.yaml | ${KUBECTL} apply -f -

echo ">> waiting for NiFi to start (first start takes a few minutes, timeout ${TIMEOUT})"
${KUBECTL} -n "${NAMESPACE}" rollout status deploy/nifi --timeout="${TIMEOUT}"
${KUBECTL} -n "${NAMESPACE}" get pods -o wide

cat <<EOF

Done. Next: ./scripts/verify.sh   (same KUBECTL setting)
EOF

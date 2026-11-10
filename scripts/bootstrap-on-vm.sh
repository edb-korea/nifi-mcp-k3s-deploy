#!/usr/bin/env bash
# One command on the k3s VM: build the sidecar image, deploy NiFi + MCP, and verify.
#
#   ./scripts/bootstrap-on-vm.sh
#
# It runs build-on-vm.sh, deploy.sh and verify.sh in order (see their headers for the settings
# they read, e.g. NIFIPILOT_REF, NIFI_PASSWORD, ROLLOUT_TIMEOUT). KUBECTL defaults to
# "sudo k3s kubectl" here. The password is asked once, by deploy.sh, unless NIFI_PASSWORD is set.
set -euo pipefail
cd "$(dirname "$0")/.."

export KUBECTL="${KUBECTL:-sudo k3s kubectl}"

echo "=== 1/3 build image on this VM ==="
./scripts/build-on-vm.sh
echo
echo "=== 2/3 deploy NiFi + MCP sidecar ==="
./scripts/deploy.sh
echo
echo "=== 3/3 verify ==="
./scripts/verify.sh

#!/usr/bin/env bash
# Copy the saved image to the k3s VM and import it into k3s' containerd.
# Runs on your workstation; needs SSH access and sudo on the VM. It asks the VM for its CPU
# architecture and sends the matching tar from dist/ (build both with build-image.sh if unsure).
#
#   ./scripts/push-image.sh ec2-user@<vm-ip>
#   SSH_OPTS="-i ~/.ssh/my-key.pem" ./scripts/push-image.sh ec2-user@<vm-ip>
#   TAR=dist/other.tar ./scripts/push-image.sh ec2-user@<vm-ip>   # skip the architecture check
set -euo pipefail
cd "$(dirname "$0")/.."

target="${1:?usage: $0 user@vm-host   (optional: SSH_OPTS=\"-i key.pem\", TAR=path)}"

# shellcheck disable=SC2086  # SSH_OPTS is intentionally word-split
if [ -z "${TAR:-}" ]; then
  machine="$(ssh ${SSH_OPTS:-} "${target}" uname -m)"
  case "${machine}" in
    x86_64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) echo "Unsupported VM architecture: ${machine}" >&2; exit 1 ;;
  esac
  TAR="$(ls -t dist/*-"${arch}".tar 2>/dev/null | head -1 || true)"
  if [ -z "${TAR}" ]; then
    echo "VM is ${machine}, but dist/ has no *-${arch}.tar." >&2
    echo "Run: PLATFORM=linux/${arch} ./scripts/build-image.sh" >&2
    exit 1
  fi
  echo ">> VM architecture: ${machine} -> ${TAR}"
fi
[ -f "${TAR}" ] || { echo "Image tar '${TAR}' not found - run scripts/build-image.sh first." >&2; exit 1; }

echo ">> copying ${TAR} to ${target}"
scp ${SSH_OPTS:-} "${TAR}" "${target}:/tmp/nifipilot-plus-image.tar"
echo ">> importing into k3s containerd"
ssh ${SSH_OPTS:-} "${target}" 'sudo k3s ctr images import /tmp/nifipilot-plus-image.tar && rm -f /tmp/nifipilot-plus-image.tar && sudo k3s ctr images ls | grep nifipilot-plus'

#!/usr/bin/env bash
# Build the nifipilot-plus sidecar image ON the k3s VM and import it into k3s' containerd.
# The image is built for the VM's own CPU architecture, so there is no cross-build and no
# image transfer from your workstation.
#
#   ./scripts/build-on-vm.sh
#   NIFIPILOT_REF=v0.1.0 ./scripts/build-on-vm.sh     # build a tag or commit instead of main
#
# Needs: git, and Docker or Podman. k3s itself ships no image builder. If you have neither:
#   Amazon Linux 2023 : sudo dnf install -y git docker && sudo systemctl enable --now docker
#   RHEL / Rocky      : sudo dnf install -y git podman
#   Ubuntu / Debian   : sudo apt-get install -y git podman      (or docker.io)
# With Docker, run this script as a user that may use it (or prefix the script with sudo).
#
# Settings (environment variables):
#   NIFIPILOT_REPO  source repository   (default https://github.com/edb-korea/nifipilot-plus)
#   NIFIPILOT_REF   branch, tag or SHA  (default main)
#   WORKDIR         where the source is cloned (default ~/.cache/nifi-mcp-k3s)
#   MCP_IMAGE       image name and tag  (default nifipilot-plus:0.1.0)
#   BUILDER         docker | podman     (default: whichever is installed, docker first)
#   K3S_CTR         command that reaches k3s' containerd (default "sudo k3s ctr")
set -euo pipefail

REPO="${NIFIPILOT_REPO:-https://github.com/edb-korea/nifipilot-plus}"
REF="${NIFIPILOT_REF:-main}"
WORKDIR="${WORKDIR:-$HOME/.cache/nifi-mcp-k3s}"
IMAGE="${MCP_IMAGE:-nifipilot-plus:0.1.0}"
K3S_CTR="${K3S_CTR:-sudo k3s ctr}"
BUILDER="${BUILDER:-}"

command -v git >/dev/null 2>&1 || { echo "git is required (e.g. sudo dnf install -y git)." >&2; exit 1; }
if [ -z "${BUILDER}" ]; then
  for candidate in docker podman; do
    if command -v "${candidate}" >/dev/null 2>&1; then BUILDER="${candidate}"; break; fi
  done
fi
if [ -z "${BUILDER}" ]; then
  echo "Neither docker nor podman is installed. See the header of this script for install commands." >&2
  exit 1
fi
command -v "${BUILDER}" >/dev/null 2>&1 || { echo "BUILDER '${BUILDER}' is not installed." >&2; exit 1; }

# Fully qualified name, so the reference k3s stores matches `image:` in the manifest
case "${IMAGE}" in
  */*) full_ref="${IMAGE}" ;;
  *) full_ref="docker.io/library/${IMAGE}" ;;
esac

src="${WORKDIR}/nifipilot-plus"
mkdir -p "${WORKDIR}"
if [ -d "${src}/.git" ]; then
  echo ">> updating ${src}"
  git -C "${src}" fetch --quiet --tags origin
else
  echo ">> cloning ${REPO}"
  git clone --quiet "${REPO}" "${src}"
fi
git -C "${src}" checkout --quiet --detach "origin/${REF}" 2>/dev/null \
  || git -C "${src}" checkout --quiet --detach "${REF}" 2>/dev/null \
  || { echo "Ref '${REF}' not found in ${REPO} (use a branch, tag or commit SHA)." >&2; exit 1; }
echo ">> building from $(git -C "${src}" log -1 --format='%h %s')"

echo ">> building ${full_ref} with ${BUILDER}"
"${BUILDER}" build -t "${full_ref}" "${src}"

echo ">> importing into k3s containerd (${K3S_CTR})"
if [ "${BUILDER}" = "podman" ]; then
  podman save --format docker-archive "${full_ref}" | ${K3S_CTR} images import -
else
  "${BUILDER}" save "${full_ref}" | ${K3S_CTR} images import -
fi
${K3S_CTR} images ls | grep nifipilot-plus
echo ">> done. Deploy with: ./scripts/deploy.sh   (after a rebuild of a running install: rollout restart, see README)"

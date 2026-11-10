#!/usr/bin/env bash
# Build the nifipilot-plus sidecar image and save it as a tar file under dist/.
# Runs on your workstation (needs Docker with buildx and a checkout of nifipilot-plus).
#
#   ./scripts/build-image.sh                       # linux/amd64 (most AWS instances)
#   PLATFORM=linux/arm64 ./scripts/build-image.sh  # Graviton instances
#
# Check the VM's architecture with `uname -m` (x86_64 = amd64, aarch64 = arm64).
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${NIFIPILOT_SRC:-../nifipilot-plus}"
PLATFORM="${PLATFORM:-linux/amd64}"
IMAGE="${MCP_IMAGE:-nifipilot-plus:0.1.0}"

if [ ! -f "$SRC/Dockerfile" ]; then
  echo "nifipilot-plus checkout not found at '$SRC' (set NIFIPILOT_SRC)." >&2
  echo "  git clone https://github.com/edb-korea/nifipilot-plus ../nifipilot-plus" >&2
  exit 1
fi

out="dist/$(echo "${IMAGE}" | tr '/:' '__')-${PLATFORM#linux/}.tar"
mkdir -p dist
echo ">> building ${IMAGE} for ${PLATFORM} from ${SRC}"
docker buildx build --platform "${PLATFORM}" --load -t "${IMAGE}" "${SRC}"
docker save "${IMAGE}" -o "${out}"
echo ">> saved ${out} ($(du -h "${out}" | cut -f1))"

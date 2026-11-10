#!/usr/bin/env bash
# Check that both containers are running and that the MCP sidecar can talk to NiFi.
# It calls the MCP server from inside its own container, so no port-forward is needed:
#
#   KUBECTL="sudo k3s kubectl" ./scripts/verify.sh
set -euo pipefail

KUBECTL="${KUBECTL:-kubectl}"
NAMESPACE="nifi"

echo ">> pod and container status"
${KUBECTL} -n "${NAMESPACE}" get pods -o wide
${KUBECTL} -n "${NAMESPACE}" get pods -l app=nifi \
  -o jsonpath='{range .items[*].status.containerStatuses[*]}{.name}{"\tready="}{.ready}{"\trestarts="}{.restartCount}{"\n"}{end}'

echo ">> calling the MCP server inside the sidecar"
${KUBECTL} -n "${NAMESPACE}" exec -i deploy/nifi -c mcp -- python - <<'PY'
import asyncio
from fastmcp import Client


async def main():
    async with Client("http://localhost:8000/mcp") as c:
        names = sorted(t.name for t in await c.list_tools())
        mode = "full (write tools enabled)" if "create_processor" in names else "readonly"
        print(f"tools: {len(names)}  mode: {mode}")
        version = (await c.call_tool("get_nifi_version", {})).structured_content
        print(f"NiFi {version['version']}  (2.x: {version['is_nifi_2x']})")
        health = (await c.call_tool("get_flow_health_status", {})).structured_content
        print("processors:", health["processors"])


asyncio.run(main())
PY
echo ">> OK: NiFi and the MCP sidecar work together"

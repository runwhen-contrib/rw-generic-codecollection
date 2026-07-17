#!/usr/bin/env bash
# End-to-end local validation: boots the stub MCP server and invokes
# mcp_tool_proxy.py directly with the env contract the Robot wrapper builds.
#
# Why not invoke runbook.robot directly here: the wrapper uses RW.Core (Import
# User Variable, Import Secret) which ships in the private runner image, not
# on PyPI. Full Robot-level testing happens inside the runner — see README.md.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CB="$(cd "$HERE/.." && pwd)"
PORT=18080

python3 "$HERE/stub_server.py" &
STUB_PID=$!
trap 'kill $STUB_PID 2>/dev/null || true' EXIT
sleep 0.3

PYBIN="$CB/.venv/bin/python"
[ -x "$PYBIN" ] || PYBIN="python3"

OUT="$(
  MCP_SERVER_URL="http://127.0.0.1:$PORT" \
  MCP_TOOL_NAME="echo" \
  MCP_TOOL_ARGS_JSON='{"msg":"hello-from-dryrun"}' \
  MCP_AUTH="stub-token" \
    "$PYBIN" "$CB/mcp_tool_proxy.py"
)"

echo "--- stdout ---"
echo "$OUT"
echo "--------------"

echo "$OUT" | grep -q 'stub-ok name=echo args={"msg": "hello-from-dryrun"}' \
  || { echo "FAIL: expected stub response not found"; exit 1; }
echo "dry-run OK"

# Local dry-run for mcp-tool-proxy

`dry-run.sh` boots `stub_server.py` (a minimal MCP HTTP server) and invokes
`mcp_tool_proxy.py` directly with the env contract the Robot wrapper would
build at runtime:

| Env var | Source in production | Value here |
|---|---|---|
| `MCP_SERVER_URL` | Runbook `configProvided` | `http://127.0.0.1:18080` |
| `MCP_TOOL_NAME` | Runbook `configProvided` | `echo` |
| `MCP_TOOL_ARGS_JSON` | Built by `runbook.robot` from `RW.Core.Import User Variable` calls | `{"msg":"hello-from-dryrun"}` |
| `MCP_AUTH` | Built by `runbook.robot` from `RW.Core.Import Secret` | `stub-token` |

## Why this bypasses `runbook.robot`

The Robot wrapper imports `RW.Core` (Import User Variable, Import Secret).
That library ships in the private RunWhen runner image, not on PyPI, so it
can't be exercised locally without that image. The script under test
(`mcp_tool_proxy.py`) is itself the part that needs end-to-end coverage with
a live HTTP server — the Robot wrapper just builds the env contract above.

Robot-level validation happens inside the runner via the standard
codecollection CI path.

## Running

```bash
./dry-run.sh
```

Exit 0 + `dry-run OK` printed = stub round-trip works.

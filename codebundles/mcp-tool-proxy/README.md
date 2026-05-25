# mcp-tool-proxy

Generic codebundle that proxies a single tool call on a private MCP server.
One SLX is auto-generated **per MCP tool** by the `mcp_tools` indexer in
`runwhen-local` (workspace-builder); this codebundle holds the constant
execution path that every generated SLX runs.

## Architecture

```
Helm values (mcpConfig) ──> workspace-builder mcp_tools indexer ──> mcp_tool resources
                                                                          │
                                                                          v
                                            .runwhen/generation-rules/mcp-tool-proxy.yaml
                                                                          │
                                                                          v
                                                       one SLX + Runbook per discovered tool
                                                                          │
                                                                          v
                              (per invocation) agentfarm → papi → runner → robot.run → mcp_tool_proxy.py
                                                                                              │
                                                                                              v
                                                                            HTTP/JSON-RPC → MCP server (in-VPC)
```

Design rationale: `docs/superpowers/specs/2026-05-20-private-mcp-integration-design.md`.

## Runtime contract

Generated Runbooks pass:

| Variable | Source | Purpose |
|---|---|---|
| `MCP_SERVER_URL` | Static `configProvided` from template | In-VPC URL of the MCP server |
| `MCP_TOOL_NAME` | Static `configProvided` from template | Tool name to invoke |
| `MCP_INPUT_SCHEMA` | Static `configProvided` from template | JSON of the tool's input_schema |
| `mcp_auth` | `secretsProvided` (workspaceKey from server's secret_ref) | Bearer token |
| `<param>` (per tool) | `runtimeVarsProvided` (rendered from input_schema.properties) | Per-invocation tool arg |

Per-invocation values are supplied by agentfarm in the RunRequest's
`runtime_var_values` map. Papi's `assemble_runbook_env`
(`backend-services-v2/papi/routers/explorer.py:496-547`) merges them into
`configProvided` with no allowlist — they appear in the runner env under
their declared names.

## Error handling

| What happened | Task outcome | Where it shows up |
|---|---|---|
| Tool returned successfully | Succeeds (rc=0) | Tool output in report |
| Tool returned a JSON-RPC error | **Succeeds** (rc=0) | Error message in report (so agentfarm can read and react) |
| Tool returned `result.isError: true` | **Succeeds** (rc=0) | `isError` message + content in report |
| `initialize` returned an error envelope | **Fails** (rc=1) | stderr — we couldn't even start an MCP session |
| Transport failure (connection refused, timeout, TLS, HTTP 5xx) | **Fails** (rc=1) | stderr |

Rationale: agentfarm needs the tool's error message to do something useful — retry, ask the user, route to a different tool. Surfacing tool errors as successful task output (with the error message in the report) preserves that signal. Reserve "failed task" for cases where we have no useful response to surface.

## Local dev

```bash
cd codebundles/mcp-tool-proxy
python3 -m venv .venv
.venv/bin/pip install -r dev-requirements.txt requests
PYTHONPATH=. .venv/bin/pytest tests/ -v
.test/dry-run.sh    # end-to-end Robot + stub MCP server
```

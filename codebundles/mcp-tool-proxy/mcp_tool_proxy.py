"""MCP tool proxy — calls a single tool on a single MCP server.

Reads the server URL, tool name, auth, and tool arguments from environment
variables (set by the Robot wrapper from the SLX's configProvided + the
runtime variables agentfarm packaged from the LLM's tool-call arguments).

Performs the standard MCP HTTP/JSON-RPC handshake:
  1. initialize
  2. notifications/initialized
  3. tools/call

Writes the tool's textual output to stdout. Exits non-zero on any protocol
or transport failure so the SLX run is marked failed.
"""

import json
import os
import sys

import requests


PROTOCOL_VERSION = "2025-03-26"
CLIENT_NAME = "runwhen-mcp-proxy"
CLIENT_VERSION = "1.0.0"
REQUEST_TIMEOUT = 30


class McpProtocolError(RuntimeError):
    """Raised when the MCP server returns a JSON-RPC error."""


def _coerce_args(tool_args: dict, schema: dict) -> dict:
    """Coerce string-valued args (from Robot's `Import User Variable`) to the
    JSON-Schema types declared in the MCP tool's input_schema. MCP servers
    schema-check the JSON-RPC payload — sending `"true"` (string) where the
    schema says `boolean` fails with `invalid_type` before the tool ever runs.

    Empty values are already filtered upstream in `runbook.robot`, so optional
    args the user didn't touch stay absent in the outgoing call.

    Coercion failures (e.g. user typed `"yep"` for a boolean) leave the value
    as the original string so the MCP server's own validator can surface the
    actual problem in its response.
    """
    properties = (schema or {}).get("properties") or {}
    coerced = {}
    for name, value in tool_args.items():
        if not isinstance(value, str):
            coerced[name] = value
            continue
        prop_type = (properties.get(name) or {}).get("type")
        if isinstance(prop_type, list):
            prop_type = next((t for t in prop_type if t != "null"), None)
        try:
            if prop_type == "boolean":
                coerced[name] = value.strip().lower() in {"true", "1", "yes", "y", "on"}
            elif prop_type == "integer":
                coerced[name] = int(value)
            elif prop_type == "number":
                coerced[name] = float(value)
            elif prop_type in ("array", "object"):
                coerced[name] = json.loads(value)
            else:
                coerced[name] = value
        except (ValueError, json.JSONDecodeError):
            coerced[name] = value
    return coerced


def _parse_response(resp):
    """Parse a JSON or SSE response body. Returns the first JSON-RPC envelope
    found, or None if nothing parseable was returned (e.g. notification ack)."""
    ct = resp.headers.get("Content-Type", "")
    if "text/event-stream" in ct:
        for line in resp.text.split("\n"):
            if line.startswith("data: "):
                try:
                    msg = json.loads(line[len("data: "):])
                    if "id" in msg or "result" in msg or "error" in msg:
                        return msg
                except json.JSONDecodeError:
                    continue
        return None
    try:
        return resp.json()
    except Exception:
        return None


def _rpc(session, url, method, params, request_id, verify=True):
    """POST a JSON-RPC request and return the parsed envelope. Envelopes
    carrying an `error` field are returned as-is — callers decide whether
    to fail (init errors) or surface as output (tool-call errors).
    Raises McpProtocolError only for malformed/empty responses where no
    envelope is available to return. Lets requests exceptions propagate
    so transport failures bubble up to main().

    `verify` is passed per-call so it overrides the REQUESTS_CA_BUNDLE env
    var that `Session.merge_environment_settings` would otherwise reapply.
    """
    resp = session.post(
        url,
        json={"jsonrpc": "2.0", "id": request_id,
              "method": method, "params": params},
        timeout=REQUEST_TIMEOUT,
        verify=verify,
    )
    resp.raise_for_status()
    sid = resp.headers.get("Mcp-Session-Id")
    if sid and "Mcp-Session-Id" not in session.headers:
        session.headers["Mcp-Session-Id"] = sid
    parsed = _parse_response(resp)
    if parsed is None:
        raise McpProtocolError(f"empty response from {method}")
    return parsed


def _notify(session, url, method, params=None, verify=True):
    """Fire-and-forget JSON-RPC notification (no `id` field, no return value)."""
    payload = {"jsonrpc": "2.0", "method": method}
    if params is not None:
        payload["params"] = params
    session.post(url, json=payload, timeout=REQUEST_TIMEOUT, verify=verify)


def render_tool_output(rpc_result):
    """Flatten MCP `result.content` (typed parts) to a single string for
    the runner's task-output channel. Text parts pass through; other types
    are serialized as JSON so nothing is silently dropped."""
    content_parts = (rpc_result.get("result") or {}).get("content", [])
    if not content_parts:
        return json.dumps(rpc_result.get("result", {}), indent=2)
    chunks = []
    for part in content_parts:
        if part.get("type") == "text":
            chunks.append(part.get("text", ""))
        else:
            chunks.append(json.dumps(part, indent=2))
    return "\n".join(chunks)


def _format_tool_error(tool_name: str, err: dict) -> str:
    code = err.get("code", "?")
    msg = err.get("message", "")
    data = err.get("data")
    out = [f"MCP tool '{tool_name}' returned error (code {code}): {msg}"]
    if data is not None:
        out.append(json.dumps(data, indent=2))
    return "\n".join(out)


def invoke_tool(server_url, tool_name, tool_args, auth_token, verify_tls=True):
    """Run the full MCP exchange for a single tool call.

    Returns the rendered tool output as a string for all cases where the
    handshake completed and the server returned a response — including tool
    errors and result.isError=true. Callers (main) treat the returned string
    as task output and exit 0.

    Raises McpProtocolError when the protocol itself fails (initialize
    returned an error envelope or session setup failed) — main translates
    those to exit 1. Transport errors (requests.RequestException) propagate
    untouched.

    `verify_tls=False` skips TLS verification — temporary escape hatch for
    runner pods whose CA bundle does not trust the MCP server's issuer.
    The proper fix is to extend the pod's CA bundle (see RW-1146).
    """
    session = requests.Session()
    session.headers.update({
        "Content-Type": "application/json",
        "Authorization": f"Bearer {auth_token}",
        "Accept": "application/json, text/event-stream",
    })
    session.verify = verify_tls
    if not verify_tls:
        try:
            from urllib3 import disable_warnings
            from urllib3.exceptions import InsecureRequestWarning
            disable_warnings(InsecureRequestWarning)
        except Exception:
            pass

    init = _rpc(session, server_url, "initialize", {
        "protocolVersion": PROTOCOL_VERSION,
        "capabilities": {},
        "clientInfo": {"name": CLIENT_NAME, "version": CLIENT_VERSION},
    }, request_id=1, verify=verify_tls)
    if "error" in init:
        err = init["error"]
        raise McpProtocolError(
            f"initialize failed (code {err.get('code')}): {err.get('message')}")

    _notify(session, server_url, "notifications/initialized", verify=verify_tls)

    rpc_result = _rpc(session, server_url, "tools/call",
                      {"name": tool_name, "arguments": tool_args},
                      request_id=2, verify=verify_tls)
    if "error" in rpc_result:
        return _format_tool_error(tool_name, rpc_result["error"])
    result = rpc_result.get("result") or {}
    if result.get("isError"):
        rendered = render_tool_output(rpc_result)
        return f"MCP tool '{tool_name}' returned isError=true:\n{rendered}"
    return render_tool_output(rpc_result)


def main():
    """Entry point. Exit-code policy:
      - 0 = handshake completed and we have a tool response (including tool
            errors and result.isError=true cases — those land in stdout so
            agentfarm can see and react to them).
      - 1 = transport failure or initialize-time protocol failure — the task
            could not produce useful tool output. stderr describes why.
    """
    server_url = os.environ["MCP_SERVER_URL"]
    tool_name  = os.environ["MCP_TOOL_NAME"]
    tool_args  = json.loads(os.environ.get("MCP_TOOL_ARGS_JSON", "") or "{}")
    auth_token = os.environ.get("MCP_AUTH", "")
    verify_tls = os.environ.get("MCP_VERIFY_TLS", "true").strip().lower() != "false"
    try:
        schema = json.loads(os.environ.get("MCP_INPUT_SCHEMA", "") or "{}")
    except json.JSONDecodeError:
        schema = {}
    tool_args = _coerce_args(tool_args, schema)

    try:
        output = invoke_tool(server_url, tool_name, tool_args, auth_token, verify_tls=verify_tls)
    except McpProtocolError as exc:
        # Protocol failure (e.g. initialize returned an error envelope).
        # Can't produce tool output → mark task failed.
        print(f"mcp_tool_proxy: {tool_name} protocol failure: {exc}",
              file=sys.stderr)
        return 1
    except requests.RequestException as exc:
        # Transport failure (connection refused, timeout, TLS, 5xx).
        print(f"mcp_tool_proxy: {tool_name} transport failure: {exc}",
              file=sys.stderr)
        return 1
    print(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())

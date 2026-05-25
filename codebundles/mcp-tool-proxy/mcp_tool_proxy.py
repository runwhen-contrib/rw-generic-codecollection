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


def _rpc(session, url, method, params, request_id):
    """POST a JSON-RPC request and return the parsed envelope. Envelopes
    carrying an `error` field are returned as-is — callers decide whether
    to fail (init errors) or surface as output (tool-call errors).
    Raises McpProtocolError only for malformed/empty responses where no
    envelope is available to return. Lets requests exceptions propagate
    so transport failures bubble up to main()."""
    resp = session.post(
        url,
        json={"jsonrpc": "2.0", "id": request_id,
              "method": method, "params": params},
        timeout=REQUEST_TIMEOUT,
    )
    resp.raise_for_status()
    sid = resp.headers.get("Mcp-Session-Id")
    if sid and "Mcp-Session-Id" not in session.headers:
        session.headers["Mcp-Session-Id"] = sid
    parsed = _parse_response(resp)
    if parsed is None:
        raise McpProtocolError(f"empty response from {method}")
    return parsed


def _notify(session, url, method, params=None):
    """Fire-and-forget JSON-RPC notification (no `id` field, no return value)."""
    payload = {"jsonrpc": "2.0", "method": method}
    if params is not None:
        payload["params"] = params
    session.post(url, json=payload, timeout=REQUEST_TIMEOUT)


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


def invoke_tool(server_url, tool_name, tool_args, auth_token):
    """Run the full MCP exchange for a single tool call.

    Returns the rendered tool output as a string for all cases where the
    handshake completed and the server returned a response — including tool
    errors and result.isError=true. Callers (main) treat the returned string
    as task output and exit 0.

    Raises McpProtocolError when the protocol itself fails (initialize
    returned an error envelope or session setup failed) — main translates
    those to exit 1. Transport errors (requests.RequestException) propagate
    untouched.
    """
    session = requests.Session()
    session.headers.update({
        "Content-Type": "application/json",
        "Authorization": f"Bearer {auth_token}",
        "Accept": "application/json, text/event-stream",
    })

    init = _rpc(session, server_url, "initialize", {
        "protocolVersion": PROTOCOL_VERSION,
        "capabilities": {},
        "clientInfo": {"name": CLIENT_NAME, "version": CLIENT_VERSION},
    }, request_id=1)
    if "error" in init:
        err = init["error"]
        raise McpProtocolError(
            f"initialize failed (code {err.get('code')}): {err.get('message')}")

    _notify(session, server_url, "notifications/initialized")

    rpc_result = _rpc(session, server_url, "tools/call",
                      {"name": tool_name, "arguments": tool_args},
                      request_id=2)
    if "error" in rpc_result:
        return _format_tool_error(tool_name, rpc_result["error"])
    result = rpc_result.get("result") or {}
    if result.get("isError"):
        rendered = render_tool_output(rpc_result)
        return f"MCP tool '{tool_name}' returned isError=true:\n{rendered}"
    return render_tool_output(rpc_result)

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

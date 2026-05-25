import json
import pytest
import requests
import responses

from mcp_tool_proxy import _rpc, _parse_response, McpProtocolError


def test_rpc_returns_parsed_result_on_json_response(mcp_server):
    mcp_server.expect_initialize(session_id="sess-x")
    session = requests.Session()
    result = _rpc(session, mcp_server.url, "initialize",
                  {"protocolVersion": "2025-03-26", "capabilities": {},
                   "clientInfo": {"name": "t", "version": "0"}},
                  request_id=1)
    assert result["jsonrpc"] == "2.0"
    assert result["id"] == 1
    assert result["result"]["protocolVersion"] == "2025-03-26"


def test_rpc_returns_error_envelope_intact(mcp_server):
    """_rpc must NOT raise on JSON-RPC error envelopes — callers (invoke_tool)
    decide whether an error is fatal (init) or surfacable as output (tools/call)."""
    mcp_server.expect_tools_call_error(code=-32601, message="method not found")
    session = requests.Session()
    parsed = _rpc(session, mcp_server.url, "tools/call",
                  {"name": "x", "arguments": {}}, request_id=1)
    assert parsed["error"]["code"] == -32601
    assert parsed["error"]["message"] == "method not found"


def test_rpc_raises_on_empty_response(mcp_server):
    """A 200 with no parseable JSON body is a protocol violation — raise."""
    import responses as _r
    mcp_server.mock.add(_r.POST, mcp_server.url, status=200, body="",
                        content_type="text/event-stream")
    session = requests.Session()
    with pytest.raises(McpProtocolError):
        _rpc(session, mcp_server.url, "tools/call", {}, request_id=1)


def test_parse_response_handles_sse():
    class FakeResp:
        headers = {"Content-Type": "text/event-stream"}
        text = 'data: {"jsonrpc":"2.0","id":1,"result":{"ok":true}}\n\n'
    parsed = _parse_response(FakeResp())
    assert parsed["result"]["ok"] is True


def test_parse_response_returns_none_for_empty_sse():
    class FakeResp:
        headers = {"Content-Type": "text/event-stream"}
        text = ""
    assert _parse_response(FakeResp()) is None

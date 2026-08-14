import json
import pytest
import requests
import responses

from mcp_tool_proxy import _rpc, _parse_response, _coerce_args, McpProtocolError


def test_coerce_args_handles_all_json_schema_types():
    schema = {"properties": {
        "includeArchived": {"type": "boolean"},
        "limit": {"type": "integer"},
        "ratio": {"type": "number"},
        "labels": {"type": "array"},
        "filter": {"type": "object"},
        "name": {"type": "string"},
        "nullable": {"type": ["string", "null"]},
    }}
    raw = {
        "includeArchived": "true", "limit": "10", "ratio": "0.5",
        "labels": '["a", "b"]', "filter": '{"k":"v"}',
        "name": "hello", "nullable": "ok",
    }
    out = _coerce_args(raw, schema)
    assert out["includeArchived"] is True
    assert out["limit"] == 10
    assert out["ratio"] == 0.5
    assert out["labels"] == ["a", "b"]
    assert out["filter"] == {"k": "v"}
    assert out["name"] == "hello"
    assert out["nullable"] == "ok"


def test_coerce_args_recognizes_common_boolean_strings():
    schema = {"properties": {"b": {"type": "boolean"}}}
    for truthy in ("true", "True", "1", "yes", "Y", "on"):
        assert _coerce_args({"b": truthy}, schema)["b"] is True
    for falsy in ("false", "0", "no", "off", "", "random"):
        assert _coerce_args({"b": falsy}, schema)["b"] is False


def test_coerce_args_passes_through_on_coercion_failure():
    """Lets the MCP server's validator surface the real error."""
    schema = {"properties": {"limit": {"type": "integer"}}}
    assert _coerce_args({"limit": "not-a-number"}, schema) == {"limit": "not-a-number"}


def test_coerce_args_skips_args_not_in_schema():
    out = _coerce_args({"foo": "bar"}, {"properties": {}})
    assert out == {"foo": "bar"}


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


from mcp_tool_proxy import _notify


def test_notify_sends_jsonrpc_without_id(mcp_server):
    mcp_server.expect_initialized_notification()
    session = requests.Session()
    _notify(session, mcp_server.url, "notifications/initialized")
    # Test passes if the callback's assertions inside conftest succeed.


from mcp_tool_proxy import render_tool_output


def test_render_collapses_text_parts():
    rpc_result = {"result": {"content": [
        {"type": "text", "text": "hello"},
        {"type": "text", "text": "world"},
    ]}}
    assert render_tool_output(rpc_result) == "hello\nworld"


def test_render_passes_through_non_text_parts_as_json():
    rpc_result = {"result": {"content": [
        {"type": "text", "text": "head"},
        {"type": "image", "data": "AAA", "mimeType": "image/png"},
    ]}}
    out = render_tool_output(rpc_result)
    assert out.startswith("head\n")
    assert '"type": "image"' in out


def test_render_falls_back_to_full_result_json_when_no_content():
    rpc_result = {"result": {"foo": "bar"}}
    assert json.loads(render_tool_output(rpc_result)) == {"foo": "bar"}


from mcp_tool_proxy import invoke_tool


def test_invoke_tool_runs_full_handshake_on_success(mcp_server):
    mcp_server.expect_initialize(session_id="sess-abc")
    mcp_server.expect_initialized_notification()
    mcp_server.expect_tools_call(
        tool_name="create_issue",
        expected_args={"project": "ENG", "summary": "Fix login bug"},
        content_parts=[{"type": "text", "text": "Created ENG-42"}],
    )

    output = invoke_tool(
        server_url=mcp_server.url,
        tool_name="create_issue",
        tool_args={"project": "ENG", "summary": "Fix login bug"},
        auth_token="t0k",
    )
    assert output == "Created ENG-42"


def test_invoke_tool_returns_error_string_on_tool_rpc_error(mcp_server):
    """tools/call returning a JSON-RPC error envelope = tool reported an
    error; surface as string output (task succeeds), don't raise."""
    mcp_server.expect_initialize()
    mcp_server.expect_initialized_notification()
    mcp_server.expect_tools_call_error(code=-32602, message="bad arg")
    output = invoke_tool(server_url=mcp_server.url, tool_name="create_issue",
                         tool_args={"project": "X"}, auth_token="t")
    assert "create_issue" in output
    assert "bad arg" in output
    assert "-32602" in output


def test_invoke_tool_returns_error_string_on_is_error_result(mcp_server):
    """tools/call returning result.isError=true also = tool reported an error."""
    mcp_server.expect_initialize()
    mcp_server.expect_initialized_notification()

    def cb(request):
        body = json.loads(request.body)
        return (200, {"Content-Type": "application/json"},
                json.dumps({"jsonrpc": "2.0", "id": body["id"],
                            "result": {"isError": True,
                                       "content": [{"type": "text",
                                                    "text": "permission denied"}]}}))
    mcp_server.mock.add_callback(responses.POST, mcp_server.url, callback=cb)

    output = invoke_tool(server_url=mcp_server.url, tool_name="delete_thing",
                         tool_args={}, auth_token="t")
    assert "delete_thing" in output
    assert "permission denied" in output


def test_invoke_tool_raises_on_initialize_error(mcp_server):
    """An error during the initialize handshake = we can't even start an MCP
    session; treat as a protocol failure (main translates to exit 1)."""
    def cb(request):
        body = json.loads(request.body)
        return (200, {"Content-Type": "application/json"},
                json.dumps({"jsonrpc": "2.0", "id": body["id"],
                            "error": {"code": -32000, "message": "unauthorized"}}))
    mcp_server.mock.add_callback(responses.POST, mcp_server.url, callback=cb)
    with pytest.raises(McpProtocolError) as excinfo:
        invoke_tool(server_url=mcp_server.url, tool_name="x",
                    tool_args={}, auth_token="t")
    assert "initialize" in str(excinfo.value)
    assert "unauthorized" in str(excinfo.value)

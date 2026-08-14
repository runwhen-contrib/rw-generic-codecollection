import json
import pytest
import responses


MCP_URL = "https://mcp.example.test/mcp"


@pytest.fixture
def mcp_server():
    """Activates `responses` and returns a small builder that registers
    expected MCP RPC handlers. Tests configure per-method behavior."""
    with responses.RequestsMock() as rsps:
        class Server:
            def __init__(self, mock):
                self.mock = mock
                self.url = MCP_URL

            def expect_initialize(self, session_id="sess-1", protocol_version="2025-03-26"):
                def cb(request):
                    body = json.loads(request.body)
                    assert body["method"] == "initialize"
                    return (
                        200,
                        {"Content-Type": "application/json", "Mcp-Session-Id": session_id},
                        json.dumps({
                            "jsonrpc": "2.0",
                            "id": body["id"],
                            "result": {
                                "protocolVersion": protocol_version,
                                "capabilities": {},
                                "serverInfo": {"name": "stub", "version": "0.0.1"},
                            },
                        }),
                    )
                self.mock.add_callback(responses.POST, self.url, callback=cb)

            def expect_initialized_notification(self):
                def cb(request):
                    body = json.loads(request.body)
                    assert body["method"] == "notifications/initialized"
                    return (200, {"Content-Type": "application/json"}, "")
                self.mock.add_callback(responses.POST, self.url, callback=cb)

            def expect_tools_call(self, tool_name, expected_args, content_parts):
                def cb(request):
                    body = json.loads(request.body)
                    assert body["method"] == "tools/call"
                    assert body["params"]["name"] == tool_name
                    assert body["params"]["arguments"] == expected_args
                    return (
                        200,
                        {"Content-Type": "application/json"},
                        json.dumps({
                            "jsonrpc": "2.0",
                            "id": body["id"],
                            "result": {"content": content_parts},
                        }),
                    )
                self.mock.add_callback(responses.POST, self.url, callback=cb)

            def expect_tools_call_error(self, code=-32000, message="bad"):
                def cb(request):
                    body = json.loads(request.body)
                    return (
                        200,
                        {"Content-Type": "application/json"},
                        json.dumps({
                            "jsonrpc": "2.0",
                            "id": body["id"],
                            "error": {"code": code, "message": message},
                        }),
                    )
                self.mock.add_callback(responses.POST, self.url, callback=cb)

        yield Server(rsps)

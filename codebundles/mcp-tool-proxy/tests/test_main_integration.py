import json
import os
import subprocess
import sys
from pathlib import Path

import pytest
import responses


SCRIPT = Path(__file__).parent.parent / "mcp_tool_proxy.py"


def _env(server_url, tool_name, args, auth="t0k"):
    return {
        **os.environ,
        "MCP_SERVER_URL": server_url,
        "MCP_TOOL_NAME": tool_name,
        "MCP_TOOL_ARGS_JSON": json.dumps(args),
        "MCP_AUTH": auth,
    }


def test_main_runs_via_subprocess_and_prints_tool_output(mcp_server):
    """End-to-end via subprocess: env vars in, stdout out, rc==0 on success.
    We can't share the `responses` mock with a subprocess, so use the in-process
    main() instead — see next test."""
    pytest.skip("subprocess + responses don't mix; covered by test_main_in_process")


def test_main_in_process_returns_zero_and_prints(mcp_server, capsys, monkeypatch):
    from mcp_tool_proxy import main

    mcp_server.expect_initialize()
    mcp_server.expect_initialized_notification()
    mcp_server.expect_tools_call(
        tool_name="echo",
        expected_args={"msg": "hi"},
        content_parts=[{"type": "text", "text": "hi back"}],
    )
    monkeypatch.setenv("MCP_SERVER_URL", mcp_server.url)
    monkeypatch.setenv("MCP_TOOL_NAME", "echo")
    monkeypatch.setenv("MCP_TOOL_ARGS_JSON", json.dumps({"msg": "hi"}))
    monkeypatch.setenv("MCP_AUTH", "tok")

    rc = main()
    captured = capsys.readouterr()
    assert rc == 0
    assert "hi back" in captured.out


def test_main_in_process_returns_zero_on_tool_error_and_prints_to_stdout(mcp_server, capsys, monkeypatch):
    """Per the design: MCP tool errors are surfaced as task OUTPUT (stdout,
    exit 0) so agentfarm can see the error message and react. Only transport
    or init failures mark the task as failed."""
    from mcp_tool_proxy import main

    mcp_server.expect_initialize()
    mcp_server.expect_initialized_notification()
    mcp_server.expect_tools_call_error(code=-32000, message="nope")
    monkeypatch.setenv("MCP_SERVER_URL", mcp_server.url)
    monkeypatch.setenv("MCP_TOOL_NAME", "x")
    monkeypatch.setenv("MCP_TOOL_ARGS_JSON", "{}")
    monkeypatch.setenv("MCP_AUTH", "tok")

    rc = main()
    captured = capsys.readouterr()
    assert rc == 0
    assert "nope" in captured.out
    assert "x" in captured.out  # tool name in error string


def test_main_in_process_returns_nonzero_on_initialize_error(mcp_server, capsys, monkeypatch):
    """initialize-time failure = task fails (exit 1, error to stderr)."""
    from mcp_tool_proxy import main

    def cb(request):
        body = json.loads(request.body)
        return (200, {"Content-Type": "application/json"},
                json.dumps({"jsonrpc": "2.0", "id": body["id"],
                            "error": {"code": -32000, "message": "unauthorized"}}))
    mcp_server.mock.add_callback(responses.POST, mcp_server.url, callback=cb)

    monkeypatch.setenv("MCP_SERVER_URL", mcp_server.url)
    monkeypatch.setenv("MCP_TOOL_NAME", "x")
    monkeypatch.setenv("MCP_TOOL_ARGS_JSON", "{}")
    monkeypatch.setenv("MCP_AUTH", "tok")

    rc = main()
    captured = capsys.readouterr()
    assert rc != 0
    assert "unauthorized" in captured.err


def test_main_in_process_returns_nonzero_on_transport_failure(capsys, monkeypatch):
    """Connection refused / unreachable server = task fails (exit 1)."""
    from mcp_tool_proxy import main

    # Point at a port nothing is listening on, with a tight timeout.
    monkeypatch.setenv("MCP_SERVER_URL", "http://127.0.0.1:1")
    monkeypatch.setenv("MCP_TOOL_NAME", "x")
    monkeypatch.setenv("MCP_TOOL_ARGS_JSON", "{}")
    monkeypatch.setenv("MCP_AUTH", "tok")

    rc = main()
    captured = capsys.readouterr()
    assert rc != 0
    assert captured.err  # something was written to stderr


def test_main_defaults_missing_args_json_to_empty(monkeypatch, mcp_server):
    from mcp_tool_proxy import main

    mcp_server.expect_initialize()
    mcp_server.expect_initialized_notification()
    mcp_server.expect_tools_call(
        tool_name="ping",
        expected_args={},
        content_parts=[{"type": "text", "text": "pong"}],
    )
    monkeypatch.setenv("MCP_SERVER_URL", mcp_server.url)
    monkeypatch.setenv("MCP_TOOL_NAME", "ping")
    monkeypatch.delenv("MCP_TOOL_ARGS_JSON", raising=False)
    monkeypatch.setenv("MCP_AUTH", "tok")

    assert main() == 0

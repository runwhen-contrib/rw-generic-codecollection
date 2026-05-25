# Private MCP Integration — Implementation Plan (Approach D)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wrap private customer MCP servers as RunWhen tasks by generating one SLX per MCP tool, using the existing runner-side workspace-builder cycle for sync, with zero agentfarm changes.

**Architecture:** A new `mcp-tool-proxy` codebundle holds a constant Python MCP client (`initialize` → `tools/call`), a Robot wrapper that dynamically imports per-tool input parameters as user variables, and a generation rule + templates that render one SLX per discovered tool. A new `mcp_tools` indexer in `runwhen-local` reads registered MCP servers from Helm-provided `mcpConfig` values (Approach D2), calls each server's `tools/list` in-VPC, and emits `mcp_tool` resources for the generation rule to match. Per-invocation arguments still flow from agentfarm via `runtime_var_values` → papi's `assemble_runbook_env` → the runner env → the Robot wrapper, with no platform allowlist needed — papi is in the *invocation* path but not in the *discovery* path.

**Tech Stack:** Python 3 (`requests`), Robot Framework (RW.Core, Process, Collections), Jinja2 generation templates, `pytest` + `responses` for tests. Runs against the existing rw-generic-codecollection Dockerfile (already includes Python + Robot).

**Scope of this plan:** (a) `codebundles/mcp-tool-proxy/` in `rw-generic-codecollection` and (b) the new `mcp_tools` indexer in `runwhen-local`. Per the **D2 decision (see defaults below)**, MCP server definitions come from the workspace-builder's Helm-provided config — **no papi or platform-side work is required for v1**. A small follow-up in `helm-charts` is needed to expose the `mcpConfig.servers` values to the workspace-builder; that's a trivial one-line values addition tracked separately.

**Defaults locked for §10 open decisions:**

| Decision | Value | Reason |
|---|---|---|
| Discovery mechanism | **D2** (Helm-defined config) | User decision 2026-05-25: defer all papi/platform changes; consume MCP servers from runner Helm config |
| SLX naming | `mcp__{server_display_name}__{tool_name}` | Spec §10.3 proposal; matches existing `mcp__` convention |
| Resource path / hierarchy | `mcp/{server_display_name}` (in `additionalContext`) | User decision 2026-05-25: groups SLXs by MCP server in the platform's resource view |
| Access tag | `read-only` for all generated SLXs | User decision 2026-05-25: provisional default until we can distinguish read-only vs. read-write MCP tools (e.g. from naming heuristics or tool annotations) |
| Probe failure | **Preserve** previous SLXs on `tools/list` failure | Spec §7.9 recommendation — avoid flap |
| On-registration UX | Wait for next builder cycle (registration is a Helm upgrade) | D2 chosen — registration is GitOps-style, not a UI flow |
| RBAC defaults | Workspace default | Out of scope for v1 |
| UI grouping | `path: mcp/{server}` in `additionalContext` + tags (`source=mcp`, `mcp_server={name}`) | No new UI surface in v1 |
| MCP transport | HTTP/JSON-RPC only | Spec §10.8 |

---

## File Structure

### `rw-generic-codecollection` (this repo)

```
codebundles/mcp-tool-proxy/
├── README.md                                       # usage + dev docs
├── runbook.robot                                   # Robot wrapper
├── mcp_tool_proxy.py                               # MCP client script
├── dev-requirements.txt                            # pytest, responses
├── tests/
│   ├── __init__.py
│   ├── conftest.py                                 # stub MCP server fixture
│   ├── test_mcp_client.py                          # unit tests
│   └── test_main_integration.py                    # env→output integration
└── .runwhen/
    ├── generation-rules/
    │   └── mcp-tool-proxy.yaml
    └── templates/
        ├── mcp-tool-proxy-slx.yaml
        └── mcp-tool-proxy-runbook.yaml
```

Responsibilities:
- `mcp_tool_proxy.py` — pure MCP client. `initialize` + `notifications/initialized` + `tools/call`. Reads env vars: `MCP_SERVER_URL`, `MCP_TOOL_NAME`, `MCP_TOOL_ARGS_JSON`, `MCP_AUTH`. Writes tool output to stdout. Exits non-zero on protocol or transport error.
- `runbook.robot` — single task `Invoke MCP Tool`. Suite Setup parses `MCP_INPUT_SCHEMA`, loops over its properties calling `RW.Core.Import User Variable` for each, packages into `tool_args_json`, hands off to the Python subprocess. Writes stdout via `RW.Core.Add Pre To Report`.
- `.runwhen/generation-rules/mcp-tool-proxy.yaml` — matches every `mcp_tool` resource, qualifies SLX names by `server_display_name` + `tool_name`, emits SLX + Runbook.
- `.runwhen/templates/mcp-tool-proxy-slx.yaml` — SLX metadata (alias, statement, tags `source=mcp` + `mcp_server={name}`, `configProvided` with `MCP_SERVER_URL`/`MCP_TOOL_NAME`/`MCP_INPUT_SCHEMA`).
- `.runwhen/templates/mcp-tool-proxy-runbook.yaml` — Runbook with codeBundle ref, static `configProvided`, `secretsProvided` for `mcp_auth`, and dynamically rendered `runtimeVarsProvided` from `match_resource.spec.input_schema.properties`.
- `tests/` — pytest suite with a `responses`-backed stub MCP server.

### `runwhen-local` (workspace-builder)

```
src/indexers/mcp_tools.py                           # new indexer
src/tests.py                                        # add MCPToolsIndexerTest cases
src/component.py                                    # register "mcp_tools" in indexers list
```

Responsibilities:
- `indexers/mcp_tools.py` — module-level `DOCUMENTATION`, `SETTINGS`, and `index(context: Context)` function. Reads the workspace's MCP server list from a new `MCP_CONFIG` setting (DICT, populated from Helm `mcpConfig:` values via the existing workspaceInfo plumbing — same pattern as `CLOUD_CONFIG_SETTING` in `src/indexers/common.py`). Then for each configured server: calls `tools/list` (in-VPC) and adds an `mcp_tool` resource per discovered tool to the Registry.
- `component.py:251` — add `"mcp_tools"` to the `Stage.INDEXER` list.
- `src/tests.py` — pytest cases that construct a `Context` with a stubbed `MCP_CONFIG` setting and `responses`-mocked `tools/list` calls, asserting the expected number/shape of resources lands in the Registry.

---

## Task Index

Tasks are grouped into 6 phases. Phases 1–3 are pure codecollection work, can run in parallel with Phase 4 (runwhen-local). Phase 5 is the end-to-end smoke test that wires both sides together. Phase 6 is documentation.

- **Phase 0** (scaffolding): T0.1 directory + dev-requirements
- **Phase 1** (Python client, TDD): T1.1–T1.6
- **Phase 2** (Robot wrapper): T2.1–T2.3
- **Phase 3** (generation rule + templates): T3.1–T3.3
- **Phase 4** (workspace-builder probe): T4.1–T4.5
- **Phase 5** (end-to-end): T5.1
- **Phase 6** (docs): T6.1

**For executing agents:** complete phases sequentially. Within a phase, tasks must be done in numeric order — later tasks depend on artifacts created earlier.

---

## Phase 0 — Scaffolding

### Task 0.1: Create codebundle directory and dev requirements

**Files:**
- Create: `codebundles/mcp-tool-proxy/dev-requirements.txt`
- Create: `codebundles/mcp-tool-proxy/tests/__init__.py` (empty)

- [ ] **Step 1: Create the codebundle directory structure**

```bash
mkdir -p codebundles/mcp-tool-proxy/tests
mkdir -p codebundles/mcp-tool-proxy/.runwhen/generation-rules
mkdir -p codebundles/mcp-tool-proxy/.runwhen/templates
touch codebundles/mcp-tool-proxy/tests/__init__.py
```

Run: `ls codebundles/mcp-tool-proxy/`
Expected: `tests` and `.runwhen` directories exist.

- [ ] **Step 2: Write dev-requirements.txt**

Path: `codebundles/mcp-tool-proxy/dev-requirements.txt`

```
pytest>=7.4
responses>=0.24
```

- [ ] **Step 3: Install dev deps in a venv**

```bash
cd codebundles/mcp-tool-proxy
python3 -m venv .venv
.venv/bin/pip install -r dev-requirements.txt requests>=2.31.0
```

Expected: clean install, no errors.

- [ ] **Step 4: Commit**

```bash
git add codebundles/mcp-tool-proxy/dev-requirements.txt codebundles/mcp-tool-proxy/tests/__init__.py
git commit -m "scaffold mcp-tool-proxy codebundle directory"
```

---

## Phase 1 — Python MCP Client (TDD)

The script is `mcp_tool_proxy.py`. Build it function-by-function. Each function gets a test first.

### Task 1.1: Stub MCP server fixture

**Files:**
- Create: `codebundles/mcp-tool-proxy/tests/conftest.py`

- [ ] **Step 1: Write the conftest**

Path: `codebundles/mcp-tool-proxy/tests/conftest.py`

```python
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
```

- [ ] **Step 2: Verify pytest collects it**

```bash
cd codebundles/mcp-tool-proxy
.venv/bin/pytest --collect-only tests/
```

Expected: 0 tests collected, no errors. (Just confirms conftest imports cleanly.)

- [ ] **Step 3: Commit**

```bash
git add codebundles/mcp-tool-proxy/tests/conftest.py
git commit -m "test: add stub MCP server fixture for mcp-tool-proxy tests"
```

---

### Task 1.2: `_rpc` helper — JSON-RPC POST, parse JSON or SSE response

> **Error policy.** `_rpc` returns the parsed JSON-RPC envelope as-is — including envelopes that carry an `error` field. It only raises `McpProtocolError` for malformed/empty responses (no envelope to return). Callers decide what to do with `error` envelopes: `initialize` errors are fatal (task fail); `tools/call` errors are surfaced as task output (task succeed). This split is what lets `main()` distinguish "transport/init failure" (exit 1) from "tool reported an error" (exit 0 + error string in stdout) per the design.

**Files:**
- Create: `codebundles/mcp-tool-proxy/tests/test_mcp_client.py`
- Create: `codebundles/mcp-tool-proxy/mcp_tool_proxy.py`

- [ ] **Step 1: Write the failing test**

Path: `codebundles/mcp-tool-proxy/tests/test_mcp_client.py`

```python
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
```

- [ ] **Step 2: Run tests, verify they fail**

```bash
cd codebundles/mcp-tool-proxy
.venv/bin/pytest tests/test_mcp_client.py -v
```

Expected: ImportError — `mcp_tool_proxy` doesn't exist yet.

- [ ] **Step 3: Implement just enough to pass**

Path: `codebundles/mcp-tool-proxy/mcp_tool_proxy.py`

```python
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
```

- [ ] **Step 4: Run tests, verify they pass**

```bash
cd codebundles/mcp-tool-proxy
PYTHONPATH=. .venv/bin/pytest tests/test_mcp_client.py -v
```

Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add codebundles/mcp-tool-proxy/mcp_tool_proxy.py codebundles/mcp-tool-proxy/tests/test_mcp_client.py
git commit -m "feat(mcp-tool-proxy): _rpc returns envelopes verbatim (callers handle errors)"
```

---

### Task 1.3: `_notify` — fire-and-forget JSON-RPC notification

**Files:**
- Modify: `codebundles/mcp-tool-proxy/tests/test_mcp_client.py`
- Modify: `codebundles/mcp-tool-proxy/mcp_tool_proxy.py`

- [ ] **Step 1: Add failing test**

Append to `tests/test_mcp_client.py`:

```python
from mcp_tool_proxy import _notify


def test_notify_sends_jsonrpc_without_id(mcp_server):
    mcp_server.expect_initialized_notification()
    session = requests.Session()
    _notify(session, mcp_server.url, "notifications/initialized")
    # Test passes if the callback's assertions inside conftest succeed.
```

- [ ] **Step 2: Run and verify failure**

```bash
PYTHONPATH=. .venv/bin/pytest tests/test_mcp_client.py::test_notify_sends_jsonrpc_without_id -v
```

Expected: ImportError on `_notify`.

- [ ] **Step 3: Implement**

Append to `mcp_tool_proxy.py`:

```python
def _notify(session, url, method, params=None):
    """Fire-and-forget JSON-RPC notification (no `id` field, no return value)."""
    payload = {"jsonrpc": "2.0", "method": method}
    if params is not None:
        payload["params"] = params
    session.post(url, json=payload, timeout=REQUEST_TIMEOUT)
```

- [ ] **Step 4: Run tests**

```bash
PYTHONPATH=. .venv/bin/pytest tests/test_mcp_client.py -v
```

Expected: 6 passed.

- [ ] **Step 5: Commit**

```bash
git add codebundles/mcp-tool-proxy/mcp_tool_proxy.py codebundles/mcp-tool-proxy/tests/test_mcp_client.py
git commit -m "feat(mcp-tool-proxy): _notify helper for JSON-RPC notifications"
```

---

### Task 1.4: `render_tool_output` — collapse MCP content array to text

**Files:**
- Modify: `codebundles/mcp-tool-proxy/tests/test_mcp_client.py`
- Modify: `codebundles/mcp-tool-proxy/mcp_tool_proxy.py`

- [ ] **Step 1: Add failing tests**

Append to `tests/test_mcp_client.py`:

```python
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
```

- [ ] **Step 2: Run and verify failure**

```bash
PYTHONPATH=. .venv/bin/pytest tests/test_mcp_client.py -v
```

Expected: ImportError on `render_tool_output`.

- [ ] **Step 3: Implement**

Append to `mcp_tool_proxy.py`:

```python
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
```

- [ ] **Step 4: Run tests**

```bash
PYTHONPATH=. .venv/bin/pytest tests/test_mcp_client.py -v
```

Expected: 9 passed.

- [ ] **Step 5: Commit**

```bash
git add codebundles/mcp-tool-proxy/mcp_tool_proxy.py codebundles/mcp-tool-proxy/tests/test_mcp_client.py
git commit -m "feat(mcp-tool-proxy): render_tool_output collapses MCP content parts"
```

---

### Task 1.5: `invoke_tool` — full handshake + error-class differentiation

**Files:**
- Modify: `codebundles/mcp-tool-proxy/tests/test_mcp_client.py`
- Modify: `codebundles/mcp-tool-proxy/mcp_tool_proxy.py`

> **Error policy reminder.** `invoke_tool` returns a string in all "the tool ran and we got a response" cases — including tool errors and `result.isError: true` cases — so `main()` can write the string to stdout and exit 0. It raises `McpProtocolError` only when the protocol itself broke (init returned an error envelope, or session couldn't be established) — `main()` translates those to exit 1. Transport errors (`requests.RequestException`) propagate untouched.

- [ ] **Step 1: Add failing tests**

Append to `tests/test_mcp_client.py`:

```python
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
```

- [ ] **Step 2: Run and verify failure**

```bash
PYTHONPATH=. .venv/bin/pytest tests/test_mcp_client.py -v
```

Expected: ImportError on `invoke_tool`.

- [ ] **Step 3: Implement**

Append to `mcp_tool_proxy.py`:

```python
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
```

- [ ] **Step 4: Run tests**

```bash
PYTHONPATH=. .venv/bin/pytest tests/test_mcp_client.py -v
```

Expected: 13 passed.

- [ ] **Step 5: Commit**

```bash
git add codebundles/mcp-tool-proxy/mcp_tool_proxy.py codebundles/mcp-tool-proxy/tests/test_mcp_client.py
git commit -m "feat(mcp-tool-proxy): invoke_tool splits init-error (raise) vs tool-error (string)"
```

---

### Task 1.6: `main()` — env-var entrypoint with non-zero exit on error

**Files:**
- Create: `codebundles/mcp-tool-proxy/tests/test_main_integration.py`
- Modify: `codebundles/mcp-tool-proxy/mcp_tool_proxy.py`

- [ ] **Step 1: Write failing tests**

Path: `codebundles/mcp-tool-proxy/tests/test_main_integration.py`

```python
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
```

- [ ] **Step 2: Run and verify failure**

```bash
PYTHONPATH=. .venv/bin/pytest tests/test_main_integration.py -v
```

Expected: ImportError on `main`.

- [ ] **Step 3: Implement `main`**

Append to `mcp_tool_proxy.py`:

```python
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

    try:
        output = invoke_tool(server_url, tool_name, tool_args, auth_token)
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
```

- [ ] **Step 4: Run all tests**

```bash
PYTHONPATH=. .venv/bin/pytest tests/ -v
```

Expected: all tests pass (1 skipped, others passing).

- [ ] **Step 5: Commit**

```bash
git add codebundles/mcp-tool-proxy/mcp_tool_proxy.py codebundles/mcp-tool-proxy/tests/test_main_integration.py
git commit -m "feat(mcp-tool-proxy): main() entrypoint reading env vars, non-zero exit on error"
```

---

## Phase 2 — Robot wrapper

### Task 2.1: Write the Robot wrapper

**Files:**
- Create: `codebundles/mcp-tool-proxy/runbook.robot`

- [ ] **Step 1: Write the wrapper**

Path: `codebundles/mcp-tool-proxy/runbook.robot`

```robot
*** Settings ***
Documentation    Proxies a single MCP tool call. Generated by the mcp-tool-proxy
...              generation rule — one SLX per MCP tool, with the tool's input
...              schema baked into MCP_INPUT_SCHEMA and per-parameter values
...              flowing in as runtime variables.
Metadata         Author    runwhen-contrib
Metadata         Display Name    MCP Tool Proxy
Metadata         Supports    mcp    generic

Library          BuiltIn
Library          RW.Core
Library          Process
Library          Collections
Library          String

Suite Setup      Suite Initialization


*** Tasks ***
Invoke MCP Tool
    [Documentation]    Calls the configured MCP tool with merged runtime arguments
    ...                and writes the tool's text response to the task report.
    [Tags]    mcp    proxy    generic

    ${rsp}=    Run Process    python3    ${CURDIR}/mcp_tool_proxy.py
    ...        env:MCP_SERVER_URL=${MCP_SERVER_URL}
    ...        env:MCP_TOOL_NAME=${MCP_TOOL_NAME}
    ...        env:MCP_TOOL_ARGS_JSON=${tool_args_json}
    ...        env:MCP_AUTH=${mcp_auth_value}
    ...        stderr=STDOUT
    RW.Core.Add Pre To Report    ${rsp.stdout}
    Should Be Equal As Integers    ${rsp.rc}    0
    ...    msg=MCP tool ${MCP_TOOL_NAME} failed (rc=${rsp.rc}); see report for details


*** Keywords ***
Suite Initialization
    ${MCP_SERVER_URL}=    RW.Core.Import User Variable    MCP_SERVER_URL
    ...    type=string    description=Full URL of the MCP server endpoint
    ${MCP_TOOL_NAME}=     RW.Core.Import User Variable    MCP_TOOL_NAME
    ...    type=string    description=Name of the MCP tool this SLX proxies
    ${schema_json}=       RW.Core.Import User Variable    MCP_INPUT_SCHEMA
    ...    type=string    description=Tool input schema (JSON)    default={}
    ${mcp_auth}=          RW.Core.Import Secret           mcp_auth
    ...    description=Bearer token for the MCP server

    ${schema}=    Evaluate    json.loads('''${schema_json}''') if '''${schema_json}''' else {}
    ...    modules=json
    ${properties}=    Evaluate    ${schema}.get('properties', {})

    # Dynamic per-parameter import. Names come from the MCP tool's input schema;
    # values are populated by papi from agentfarm's runtime_var_values payload
    # via explorer.py's assemble_runbook_env merge (no allowlist at that layer).
    ${tool_args}=    Create Dictionary
    @{param_names}=    Get Dictionary Keys    ${properties}
    FOR    ${pname}    IN    @{param_names}
        ${val}=    RW.Core.Import User Variable    ${pname}
        ...        type=string    description=MCP tool input parameter    default=${EMPTY}
        Run Keyword If    '''${val}''' != '${EMPTY}'
        ...    Set To Dictionary    ${tool_args}    ${pname}    ${val}
    END
    ${tool_args_json}=    Evaluate    json.dumps(${tool_args})    modules=json
    ${mcp_auth_value}=    Set Variable    ${mcp_auth.value}

    Set Suite Variable    ${MCP_SERVER_URL}
    Set Suite Variable    ${MCP_TOOL_NAME}
    Set Suite Variable    ${tool_args_json}
    Set Suite Variable    ${mcp_auth_value}
```

- [ ] **Step 2: Syntax-check the Robot file**

```bash
cd codebundles/mcp-tool-proxy
.venv/bin/pip install robotframework
.venv/bin/python -c "from robot.api import get_model; get_model('runbook.robot')"
```

Expected: no exception.

- [ ] **Step 3: Commit**

```bash
git add codebundles/mcp-tool-proxy/runbook.robot
git commit -m "feat(mcp-tool-proxy): Robot wrapper with dynamic schema-driven runtime vars"
```

---

### Task 2.2: Robot dry-run against the stub MCP server

**Files:**
- Create: `codebundles/mcp-tool-proxy/.test/dry-run.sh`
- Create: `codebundles/mcp-tool-proxy/.test/stub_server.py`

Goal: a script that boots a tiny in-process MCP server, then runs `robot` against the Robot file with `MCP_SERVER_URL` pointing at it. Validates the Robot + Python integration end-to-end without needing the platform.

- [ ] **Step 1: Write a tiny stub server**

Path: `codebundles/mcp-tool-proxy/.test/stub_server.py`

```python
"""Minimal HTTP MCP stub for local dry-runs of the Robot wrapper.
Listens on $PORT (default 18080), accepts initialize/notifications/tools/call,
echoes back a canned text response."""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(length) or b"{}")
        method = body.get("method", "")
        if method == "initialize":
            resp = {"jsonrpc": "2.0", "id": body["id"],
                    "result": {"protocolVersion": "2025-03-26",
                               "capabilities": {},
                               "serverInfo": {"name": "stub", "version": "0"}}}
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Mcp-Session-Id", "stub-session")
            self.end_headers()
            self.wfile.write(json.dumps(resp).encode())
        elif method == "notifications/initialized":
            self.send_response(200)
            self.end_headers()
        elif method == "tools/call":
            args = body["params"].get("arguments", {})
            text = f"stub-ok name={body['params']['name']} args={json.dumps(args)}"
            resp = {"jsonrpc": "2.0", "id": body["id"],
                    "result": {"content": [{"type": "text", "text": text}]}}
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(resp).encode())
        else:
            self.send_response(400)
            self.end_headers()

    def log_message(self, *_args, **_kw):
        return


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "18080"))
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()
```

- [ ] **Step 2: Write the dry-run script**

Path: `codebundles/mcp-tool-proxy/.test/dry-run.sh`

```bash
#!/usr/bin/env bash
# Boots the stub MCP server, runs the Robot wrapper against it, asserts success.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CB="$(cd "$HERE/.." && pwd)"
PORT=18080

python3 "$HERE/stub_server.py" &
STUB_PID=$!
trap 'kill $STUB_PID 2>/dev/null || true' EXIT
sleep 0.3

# Use the schema to drive a dynamic import: a single parameter `msg`.
SCHEMA='{"type":"object","properties":{"msg":{"type":"string"}}}'

# Robot expects a secret file path for `mcp_auth`. Write a fake one.
SECRET_FILE="$(mktemp)"
echo "stub-token" > "$SECRET_FILE"

cd "$CB"
robot \
  --variable MCP_SERVER_URL:http://127.0.0.1:$PORT \
  --variable MCP_TOOL_NAME:echo \
  --variable "MCP_INPUT_SCHEMA:$SCHEMA" \
  --variable msg:hello-from-dryrun \
  --variable "mcp_auth:$SECRET_FILE" \
  --outputdir "$HERE/_output" \
  runbook.robot

grep -q "stub-ok name=echo args={\"msg\": \"hello-from-dryrun\"}" "$HERE/_output/report.html" \
  || { echo "FAIL: expected stub response not found in report"; exit 1; }
echo "dry-run OK"
```

- [ ] **Step 3: Make executable and run**

```bash
chmod +x codebundles/mcp-tool-proxy/.test/dry-run.sh
codebundles/mcp-tool-proxy/.test/dry-run.sh
```

Expected: `dry-run OK` printed; `report.html` written to `.test/_output/`.

> **Note:** Robot's `RW.Core.Import Secret` resolves a real platform secret. If running outside the platform fails because of this, swap to a local stub by skipping the secret-resolution path (e.g. pass `MCP_AUTH` directly via env). Document the limitation in `.test/README.md` if you hit this.

- [ ] **Step 4: Commit**

```bash
git add codebundles/mcp-tool-proxy/.test/dry-run.sh codebundles/mcp-tool-proxy/.test/stub_server.py
git commit -m "test(mcp-tool-proxy): local dry-run script for the Robot wrapper"
```

---

### Task 2.3: Add `.test/_output/` to gitignore

**Files:**
- Modify: `codebundles/mcp-tool-proxy/.gitignore` (create)

- [ ] **Step 1: Write gitignore**

Path: `codebundles/mcp-tool-proxy/.gitignore`

```
.venv/
.test/_output/
__pycache__/
*.pyc
.pytest_cache/
```

- [ ] **Step 2: Commit**

```bash
git add codebundles/mcp-tool-proxy/.gitignore
git commit -m "chore(mcp-tool-proxy): gitignore venv/test output/pycache"
```

---

## Phase 3 — Generation rule + templates

### Task 3.1: Generation rule

**Files:**
- Create: `codebundles/mcp-tool-proxy/.runwhen/generation-rules/mcp-tool-proxy.yaml`

- [ ] **Step 1: Write the rule**

```yaml
apiVersion: runwhen.com/v1
kind: GenerationRules
spec:
  platform: mcp
  generationRules:
    - resourceTypes:
        - mcp:mcp_tool
      matchRules:
        - type: pattern
          pattern: ".+"
          properties: [tool_name]
          mode: substring
      slxs:
        - baseName: mcp-tool
          levelOfDetail: basic
          qualifiers: [server_display_name, tool_name]
          baseTemplateName: mcp-tool-proxy
          outputItems:
            - type: slx
              templateName: mcp-tool-proxy-slx.yaml
            - type: runbook
              templateName: mcp-tool-proxy-runbook.yaml
```

- [ ] **Step 2: Validate against runwhen-local's schema (best-effort)**

```bash
cd /Users/prats/Documents/work/runwhen-local
python3 -c "
import json, yaml
schema = json.load(open('src/generation-rule-schema.json'))
data = yaml.safe_load(open('/Users/prats/Documents/work/rw-generic-codecollection/codebundles/mcp-tool-proxy/.runwhen/generation-rules/mcp-tool-proxy.yaml'))
import jsonschema
jsonschema.validate(data, schema)
print('OK')
"
```

Expected: `OK`. If `jsonschema` is missing, `pip install jsonschema` first. If the local schema doesn't load, document the discrepancy and proceed — the rule will be validated when the workspace-builder runs it in Phase 5.

- [ ] **Step 3: Commit**

```bash
git add codebundles/mcp-tool-proxy/.runwhen/generation-rules/mcp-tool-proxy.yaml
git commit -m "feat(mcp-tool-proxy): generation rule matching mcp_tool resources"
```

---

### Task 3.2: SLX template

**Files:**
- Create: `codebundles/mcp-tool-proxy/.runwhen/templates/mcp-tool-proxy-slx.yaml`

- [ ] **Step 1: Write the template**

```yaml
apiVersion: runwhen.com/v1
kind: ServiceLevelX
metadata:
  name: {{slx_name}}
  labels: {% include "common-labels.yaml" %}
spec:
  alias: "MCP: {{match_resource.spec.server_display_name}} / {{match_resource.spec.tool_name}}"
  statement: "{{match_resource.spec.description | default('Proxy for ' ~ match_resource.spec.tool_name) | replace('\"', '\\\"')}}"
  configProvided:
    - name: MCP_SERVER_URL
      value: {{match_resource.spec.server_url}}
    - name: MCP_TOOL_NAME
      value: {{match_resource.spec.tool_name}}
    - name: MCP_INPUT_SCHEMA
      value: '{{match_resource.spec.input_schema | tojson}}'
  additionalContext:
    path: "mcp/{{match_resource.spec.server_display_name}}"
    hierarchy: "mcp/{{match_resource.spec.server_display_name}}"
    mcp_server_id: "{{match_resource.spec.server_id}}"
    mcp_tool_name: "{{match_resource.spec.tool_name}}"
  tags:
    - name: source
      value: mcp
    - name: mcp_server
      value: "{{match_resource.spec.server_display_name}}"
    - name: access
      value: read-only
```

- [ ] **Step 2: Render-test the template with a synthetic resource**

```bash
cd /Users/prats/Documents/work/rw-generic-codecollection
python3 <<'PY'
import jinja2
env = jinja2.Environment(loader=jinja2.FileSystemLoader('codebundles/mcp-tool-proxy/.runwhen/templates'))
# Add a stub for the {% include 'common-labels.yaml' %} so the template renders
env.loader.mapping = {'common-labels.yaml': '{ stub: true }'}
env.loader = jinja2.ChoiceLoader([env.loader, jinja2.DictLoader({'common-labels.yaml': '{ stub: true }'})])
t = env.get_template('mcp-tool-proxy-slx.yaml')
class R: pass
r = R(); r.spec = type('S', (), {
    'server_display_name': 'jira', 'tool_name': 'create_issue',
    'server_url': 'https://jira-mcp.internal/mcp', 'server_id': 'uuid-x',
    'description': 'Create a Jira issue',
    'input_schema': {'type': 'object', 'properties': {'project': {'type': 'string'}}, 'required': ['project']},
})()
print(t.render(slx_name='mcp-jira-create-issue', match_resource=r))
PY
```

Expected: valid YAML printed (no Jinja errors). Eyeball that alias, configProvided, tags look right.

- [ ] **Step 3: Commit**

```bash
git add codebundles/mcp-tool-proxy/.runwhen/templates/mcp-tool-proxy-slx.yaml
git commit -m "feat(mcp-tool-proxy): SLX template with per-tool config + mcp tags"
```

---

### Task 3.3: Runbook template

**Files:**
- Create: `codebundles/mcp-tool-proxy/.runwhen/templates/mcp-tool-proxy-runbook.yaml`

- [ ] **Step 1: Write the template**

```yaml
apiVersion: runwhen.com/v1
kind: Runbook
metadata:
  name: {{slx_name}}
spec:
  location: {{default_location}}
  codeBundle:
    repoUrl: https://github.com/runwhen-contrib/rw-generic-codecollection.git
    ref: main
    pathToRobot: codebundles/mcp-tool-proxy/runbook.robot
  # Static — same for every invocation of this SLX.
  configProvided:
    - name: MCP_SERVER_URL
      value: {{match_resource.spec.server_url}}
    - name: MCP_TOOL_NAME
      value: {{match_resource.spec.tool_name}}
    - name: MCP_INPUT_SCHEMA
      value: '{{match_resource.spec.input_schema | tojson}}'
  secretsProvided:
    - name: mcp_auth
      workspaceKey: {{match_resource.spec.secret_ref}}
  # Dynamic per-invocation. Rendered from the MCP tool's input_schema.properties.
  # Values are supplied by agentfarm at task-run time and merged into the runner
  # env by papi's assemble_runbook_env (explorer.py:496-547) — no allowlist or
  # pre-declaration check at that layer; arbitrary keys are accepted.
  runtimeVarsProvided:
    {% for pname, pschema in (match_resource.spec.input_schema.properties | default({})).items() %}
    - name: {{pname}}
      type: {{pschema.type | default("string")}}
      description: "{{pschema.description | default('') | replace('\"', '\\\"')}}"
      {% if pschema.default is defined %}default: {{pschema.default | tojson}}{% endif %}
      required: {{pname in (match_resource.spec.input_schema.required | default([]))}}
    {% endfor %}
```

- [ ] **Step 2: Render-test**

```bash
cd /Users/prats/Documents/work/rw-generic-codecollection
python3 <<'PY'
import jinja2, yaml
env = jinja2.Environment(loader=jinja2.FileSystemLoader('codebundles/mcp-tool-proxy/.runwhen/templates'))
t = env.get_template('mcp-tool-proxy-runbook.yaml')
class R: pass
r = R(); r.spec = type('S', (), {
    'server_url': 'https://jira-mcp.internal/mcp',
    'tool_name': 'create_issue',
    'secret_ref': 'jira-mcp-token',
    'input_schema': {'type': 'object',
                     'properties': {
                         'project': {'type': 'string', 'description': 'Project key'},
                         'summary': {'type': 'string'},
                         'priority': {'type': 'string', 'default': 'P3'},
                     },
                     'required': ['project', 'summary']},
})()
out = t.render(slx_name='mcp-jira-create-issue', default_location='loc1', match_resource=r)
print(out)
parsed = yaml.safe_load(out)
assert parsed['spec']['runtimeVarsProvided'][0]['name'] in {'project','summary','priority'}
assert any(v.get('required') is True for v in parsed['spec']['runtimeVarsProvided'])
assert any(v.get('default') == 'P3' for v in parsed['spec']['runtimeVarsProvided'])
print('OK')
PY
```

Expected: valid YAML printed, `OK` at the end.

- [ ] **Step 3: Commit**

```bash
git add codebundles/mcp-tool-proxy/.runwhen/templates/mcp-tool-proxy-runbook.yaml
git commit -m "feat(mcp-tool-proxy): Runbook template with dynamic runtimeVarsProvided"
```

---

## Phase 4 — Workspace-builder probe (runwhen-local)

> **IMPORTANT — repo switch.** Tasks 4.1–4.5 live in `/Users/prats/Documents/work/runwhen-local`, not in this codecollection. Before starting, `cd` into that repo and create a feature branch:
> ```bash
> cd /Users/prats/Documents/work/runwhen-local
> git checkout -b feat/mcp-tools-indexer
> ```

### Task 4.1: Add the `MCP_CONFIG` setting and indexer skeleton

**Files:**
- Create: `/Users/prats/Documents/work/runwhen-local/src/indexers/mcp_tools.py`

- [ ] **Step 1: Write the skeleton**

Path: `src/indexers/mcp_tools.py`

```python
"""Indexer that discovers MCP tools by:
  1. Reading the workspace's MCP server list from the MCP_CONFIG setting
     (populated from Helm `mcpConfig:` values via the runner's existing
     workspaceInfo plumbing — Approach D2).
  2. For each configured server, calling its `tools/list` MCP endpoint
     (in-VPC, outbound from the runner).
  3. Emitting one `mcp_tool` resource per tool to the Registry, with the
     server's URL/secret-ref/display-name and the tool's input schema.

A subsequent generation-rule run (enrichers/generation_rules) matches these
resources and renders one SLX + Runbook per tool via the mcp-tool-proxy
templates in rw-generic-codecollection.
"""

import logging
from typing import Any

import requests

from component import Setting, SettingDependency, Context
from resources import Registry, REGISTRY_PROPERTY_NAME

logger = logging.getLogger(__name__)

DOCUMENTATION = "Discovers MCP tools from Helm-configured MCP servers (Approach D2)."

# Same pattern as CLOUD_CONFIG_SETTING in src/indexers/common.py — a DICT
# setting populated from the workspaceInfo YAML's `mcpConfig:` key, which the
# runner Helm chart writes from its values.yaml `mcpConfig:` block:
#
#   mcpConfig:
#     servers:
#       - display_name: jira
#         url: https://jira-mcp.internal:443/mcp
#         secret_ref: jira-mcp-token
#       - display_name: linear
#         url: https://linear-mcp.internal:443/mcp
#         secret_ref: linear-mcp-token
MCP_CONFIG_SETTING = Setting(
    "MCP_CONFIG",
    "mcpConfig",
    Setting.Type.DICT,
    "Configuration for MCP servers to introspect for tool discovery.",
    dict(),
)

SETTINGS = (
    SettingDependency(MCP_CONFIG_SETTING, False),
)

PLATFORM_NAME = "mcp"
RESOURCE_TYPE = "mcp_tool"
TOOLS_LIST_TIMEOUT = 15


def index(context: Context) -> None:
    config = context.get_setting(MCP_CONFIG_SETTING) or {}
    servers = _load_servers_from_setting(config, on_warning=context.add_warning)
    if not servers:
        logger.info("mcp_tools: no MCP servers configured; skipping.")
        return

    registry: Registry = context.get_property(REGISTRY_PROPERTY_NAME)

    for server in servers:
        try:
            tools = _list_tools(server)
        except Exception as exc:
            # Preserve previous SLXs on failure (per design §7.9). We simply
            # don't emit fresh resources for this server; the existing SLXs
            # from the previous successful cycle stay in place upstream.
            logger.warning("mcp_tools: tools/list failed for %s: %s",
                           server.get("display_name"), exc)
            context.add_warning(
                f"MCP tools/list failed for {server.get('display_name')}: {exc}")
            continue
        for tool in tools:
            _emit_tool_resource(registry, server, tool)
```

- [ ] **Step 2: Verify it parses**

```bash
cd /Users/prats/Documents/work/runwhen-local
python3 -c "import sys; sys.path.insert(0, 'src'); from indexers import mcp_tools; print(mcp_tools.DOCUMENTATION)"
```

Expected: the documentation string is printed.

- [ ] **Step 3: Commit**

```bash
git add src/indexers/mcp_tools.py
git commit -m "feat(indexer): scaffold mcp_tools indexer with settings"
```

---

### Task 4.2: Implement `_load_servers_from_setting` (TDD)

**Files:**
- Modify: `/Users/prats/Documents/work/runwhen-local/src/tests.py`
- Modify: `/Users/prats/Documents/work/runwhen-local/src/indexers/mcp_tools.py`

- [ ] **Step 1: Add failing tests**

Append to `src/tests.py`:

```python
from unittest import TestCase, mock

from indexers import mcp_tools


class LoadServersFromSettingTest(TestCase):
    def test_returns_servers_list_from_well_formed_config(self):
        config = {"servers": [
            {"display_name": "jira",
             "url": "https://jira-mcp.internal/mcp",
             "secret_ref": "jira-mcp-token"},
            {"display_name": "linear",
             "url": "https://linear-mcp.internal/mcp",
             "secret_ref": "linear-mcp-token"},
        ]}
        servers = mcp_tools._load_servers_from_setting(config)
        self.assertEqual(len(servers), 2)
        self.assertEqual(servers[0]["display_name"], "jira")

    def test_returns_empty_when_no_servers_key(self):
        self.assertEqual(mcp_tools._load_servers_from_setting({}), [])
        self.assertEqual(mcp_tools._load_servers_from_setting(None), [])

    def test_skips_entries_missing_required_fields_and_warns(self):
        warnings = []
        config = {"servers": [
            {"display_name": "ok",
             "url": "https://ok.internal/mcp",
             "secret_ref": "ok-token"},
            {"display_name": "broken"},  # missing url + secret_ref
            {"url": "https://anon.internal/mcp",
             "secret_ref": "anon-token"},  # missing display_name
        ]}
        servers = mcp_tools._load_servers_from_setting(
            config, on_warning=warnings.append)
        self.assertEqual([s["display_name"] for s in servers], ["ok"])
        self.assertEqual(len(warnings), 2)
        self.assertTrue(any("broken" in w for w in warnings))
```

- [ ] **Step 2: Run, verify failure**

```bash
cd /Users/prats/Documents/work/runwhen-local
PYTHONPATH=src python3 -m pytest src/tests.py::LoadServersFromSettingTest -v
```

Expected: AttributeError (function not implemented).

- [ ] **Step 3: Implement**

Append to `src/indexers/mcp_tools.py`:

```python
REQUIRED_SERVER_FIELDS = ("display_name", "url", "secret_ref")


def _load_servers_from_setting(config, on_warning=None) -> list[dict[str, Any]]:
    """Parse the MCP_CONFIG setting (a DICT mirroring the Helm values block)
    into a list of validated server entries. Skips malformed entries with a
    warning so a single bad config row doesn't prevent the rest from working.
    """
    if not config:
        return []
    raw = config.get("servers") or []
    valid: list[dict[str, Any]] = []
    for entry in raw:
        if not isinstance(entry, dict):
            if on_warning:
                on_warning(f"mcpConfig.servers entry is not a dict: {entry!r}")
            continue
        missing = [f for f in REQUIRED_SERVER_FIELDS if not entry.get(f)]
        if missing:
            label = entry.get("display_name") or entry.get("url") or "<unnamed>"
            if on_warning:
                on_warning(
                    f"mcpConfig.servers[{label}] missing required field(s) "
                    f"{missing}; skipping")
            continue
        valid.append(entry)
    return valid
```

- [ ] **Step 4: Run tests**

```bash
PYTHONPATH=src python3 -m pytest src/tests.py::LoadServersFromSettingTest -v
```

Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add src/indexers/mcp_tools.py src/tests.py
git commit -m "feat(indexer): _load_servers_from_setting parses MCP_CONFIG with validation"
```

---

### Task 4.3: Implement `_list_tools` (TDD)

**Files:**
- Modify: `/Users/prats/Documents/work/runwhen-local/src/tests.py`
- Modify: `/Users/prats/Documents/work/runwhen-local/src/indexers/mcp_tools.py`

- [ ] **Step 1: Add failing tests**

Append to `src/tests.py`:

```python
class ListToolsTest(TestCase):
    @responses.activate
    def test_lists_tools_via_initialize_and_tools_list(self):
        url = "https://jira-mcp.internal/mcp"

        def init_cb(request):
            body = json.loads(request.body)
            assert body["method"] == "initialize"
            return (200, {"Content-Type": "application/json",
                          "Mcp-Session-Id": "s1"},
                    json.dumps({"jsonrpc": "2.0", "id": body["id"],
                                "result": {"protocolVersion": "2025-03-26",
                                           "capabilities": {},
                                           "serverInfo": {"name": "x", "version": "0"}}}))

        def notify_or_list_cb(request):
            body = json.loads(request.body)
            if body.get("method") == "notifications/initialized":
                return (200, {}, "")
            assert body["method"] == "tools/list"
            return (200, {"Content-Type": "application/json"},
                    json.dumps({"jsonrpc": "2.0", "id": body["id"],
                                "result": {"tools": [
                                    {"name": "create_issue",
                                     "description": "Create a Jira issue",
                                     "inputSchema": {"type": "object",
                                                     "properties": {"project": {"type": "string"}},
                                                     "required": ["project"]}},
                                ]}}))

        responses.add_callback(responses.POST, url, callback=init_cb)
        responses.add_callback(responses.POST, url, callback=notify_or_list_cb)
        responses.add_callback(responses.POST, url, callback=notify_or_list_cb)

        server = {"display_name": "jira", "url": url, "secret_ref": "tok"}
        tools = mcp_tools._list_tools(server, fetch_secret=lambda _: "stub-token")
        self.assertEqual(len(tools), 1)
        self.assertEqual(tools[0]["name"], "create_issue")
        self.assertEqual(tools[0]["inputSchema"]["required"], ["project"])
```

(Add `import json` to `tests.py` if missing.)

- [ ] **Step 2: Run, verify failure**

```bash
PYTHONPATH=src python3 -m pytest src/tests.py::ListToolsTest -v
```

Expected: AttributeError on `_list_tools`.

- [ ] **Step 3: Implement**

Append to `src/indexers/mcp_tools.py`:

```python
def _resolve_secret(secret_ref: str) -> str:
    """Read a workspace secret and return the token value. Resolved here so
    tests can monkey-patch this single function rather than threading a
    fetcher parameter through every call site."""
    from k8s_utils import get_secret
    data = get_secret(secret_ref)
    # Secret convention: stored under key "token"; fall back to single-key shape.
    return data.get("token") or next(iter(data.values()))


def _list_tools(server: dict[str, Any],
                fetch_secret=None) -> list[dict[str, Any]]:
    """Calls the MCP server's initialize/notifications/tools/list handshake
    and returns the `tools` array from the result.

    `fetch_secret` is injected for testability. Defaults to _resolve_secret
    which talks to the k8s secret store at runtime.
    """
    if fetch_secret is None:
        fetch_secret = _resolve_secret
    token = fetch_secret(server["secret_ref"])

    s = requests.Session()
    s.headers.update({
        "Content-Type": "application/json",
        "Authorization": f"Bearer {token}",
        "Accept": "application/json, text/event-stream",
    })
    init = s.post(server["url"],
                  json={"jsonrpc": "2.0", "id": 1, "method": "initialize",
                        "params": {"protocolVersion": "2025-03-26",
                                   "capabilities": {},
                                   "clientInfo": {"name": "runwhen-builder", "version": "1.0.0"}}},
                  timeout=TOOLS_LIST_TIMEOUT)
    init.raise_for_status()
    sid = init.headers.get("Mcp-Session-Id")
    if sid:
        s.headers["Mcp-Session-Id"] = sid
    s.post(server["url"],
           json={"jsonrpc": "2.0", "method": "notifications/initialized"},
           timeout=TOOLS_LIST_TIMEOUT)
    resp = s.post(server["url"],
                  json={"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
                  timeout=TOOLS_LIST_TIMEOUT)
    resp.raise_for_status()
    parsed = resp.json()
    if "error" in parsed:
        raise RuntimeError(f"tools/list error: {parsed['error']}")
    return parsed.get("result", {}).get("tools", [])
```

- [ ] **Step 4: Run tests**

```bash
PYTHONPATH=src python3 -m pytest src/tests.py::ListToolsTest -v
```

Expected: 1 passed.

- [ ] **Step 5: Commit**

```bash
git add src/indexers/mcp_tools.py src/tests.py
git commit -m "feat(indexer): _list_tools performs MCP handshake and returns tool array"
```

---

### Task 4.4: Implement `_emit_tool_resource` and full `index()` integration (TDD)

**Files:**
- Modify: `/Users/prats/Documents/work/runwhen-local/src/tests.py`
- Modify: `/Users/prats/Documents/work/runwhen-local/src/indexers/mcp_tools.py`

- [ ] **Step 1: Add failing tests**

Append to `src/tests.py`:

```python
from resources import Registry, REGISTRY_PROPERTY_NAME
from component import Context


class EmitToolResourceTest(TestCase):
    def test_emits_resource_with_expected_shape(self):
        reg = Registry()
        server = {"server_id": "u1", "display_name": "jira",
                  "url": "https://jira-mcp.internal/mcp",
                  "secret_ref": "jira-mcp-token"}
        tool = {"name": "create_issue",
                "description": "Create a Jira issue",
                "inputSchema": {"type": "object",
                                "properties": {"project": {"type": "string"}},
                                "required": ["project"]}}
        mcp_tools._emit_tool_resource(reg, server, tool)

        rt = reg.lookup_resource_type("mcp", "mcp_tool")
        self.assertIsNotNone(rt)
        self.assertEqual(len(rt.instances), 1)
        res = next(iter(rt.instances.values()))
        self.assertEqual(res.spec["server_display_name"], "jira")
        self.assertEqual(res.spec["tool_name"], "create_issue")
        self.assertEqual(res.spec["secret_ref"], "jira-mcp-token")
        self.assertEqual(res.spec["input_schema"]["required"], ["project"])

    def test_index_skips_when_config_empty(self):
        ctx = Context({}, mock.MagicMock())
        ctx.set_property(REGISTRY_PROPERTY_NAME, Registry())
        mcp_tools.index(ctx)  # should not raise
        reg = ctx.get_property(REGISTRY_PROPERTY_NAME)
        self.assertEqual(reg.platforms, {})

    def test_index_preserves_on_tools_list_failure(self):
        # MCP_CONFIG lists one server; tools/list raises → no resources
        # emitted, warning recorded, no exception propagated.
        ctx = Context({
            "MCP_CONFIG": {"servers": [
                {"display_name": "jira",
                 "url": "https://jira-mcp.internal/mcp",
                 "secret_ref": "tok"},
            ]},
        }, mock.MagicMock())
        ctx.set_property(REGISTRY_PROPERTY_NAME, Registry())
        with mock.patch.object(mcp_tools, "_list_tools",
                               side_effect=RuntimeError("boom")) as patched:
            mcp_tools.index(ctx)
            self.assertEqual(patched.call_count, 1)
        reg = ctx.get_property(REGISTRY_PROPERTY_NAME)
        self.assertEqual(reg.platforms, {})
        self.assertTrue(any("boom" in w for w in ctx.warnings))
```

- [ ] **Step 2: Run, verify failure**

```bash
PYTHONPATH=src python3 -m pytest src/tests.py::EmitToolResourceTest -v
```

Expected: AttributeError on `_emit_tool_resource`.

- [ ] **Step 3: Implement**

Append to `src/indexers/mcp_tools.py`:

```python
def _emit_tool_resource(registry: Registry,
                        server: dict[str, Any],
                        tool: dict[str, Any]) -> None:
    """Add one `mcp_tool` resource to the registry under platform=mcp."""
    server_name = server["display_name"]
    tool_name = tool["name"]
    qualified = f"{server_name}__{tool_name}"
    spec = {
        "server_id": server.get("server_id"),
        "server_display_name": server_name,
        "server_url": server["url"],
        "secret_ref": server["secret_ref"],
        "tool_name": tool_name,
        "description": tool.get("description", ""),
        "input_schema": tool.get("inputSchema") or tool.get("input_schema") or {
            "type": "object", "properties": {}, "required": [],
        },
    }
    registry.add_resource(
        platform_name=PLATFORM_NAME,
        resource_type_name=RESOURCE_TYPE,
        resource_name=qualified,
        resource_qualified_name=qualified,
        resource_attributes={"spec": spec},
    )
```

- [ ] **Step 4: Run tests**

```bash
PYTHONPATH=src python3 -m pytest src/tests.py -v
```

Expected: all new tests pass; previously passing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add src/indexers/mcp_tools.py src/tests.py
git commit -m "feat(indexer): _emit_tool_resource + index() drift-preserving on failure"
```

---

### Task 4.5: Register the indexer in `component.py`

**Files:**
- Modify: `/Users/prats/Documents/work/runwhen-local/src/component.py`

- [ ] **Step 1: Add `"mcp_tools"` to the indexer list**

Find the `component_stages_init` block (around `src/component.py:250`) and add `"mcp_tools"` to the indexer tuple.

```python
component_stages_init = (
    (Stage.INDEXER, ["load_resources", "kubeapi", "cloudquery", "azure_devops", "mcp_tools"]),
    (Stage.ENRICHER, ["generation_rules"]),
    (Stage.RENDERER, ["render_output_items", "dump_resources"])
)
```

- [ ] **Step 2: Confirm component is discoverable**

```bash
PYTHONPATH=src python3 -c "
from component import init_components, all_components
init_components()
assert 'mcp_tools' in all_components, list(all_components.keys())
print('mcp_tools component registered')
"
```

Expected: `mcp_tools component registered`.

- [ ] **Step 3: Run full test suite**

```bash
PYTHONPATH=src python3 -m pytest src/tests.py -v
```

Expected: every test passes.

- [ ] **Step 4: Commit**

```bash
git add src/component.py
git commit -m "feat(workspace-builder): register mcp_tools indexer in component pipeline"
```

---

## Phase 5 — End-to-end integration smoke test

### Task 5.1: Render SLX + Runbook from a real indexer-produced registry

**Files:**
- Create: `/Users/prats/Documents/work/runwhen-local/src/tests.py` (append)

This test exercises the full path: Helm-style MCP_CONFIG → stub MCP `tools/list` → indexer produces resources → generation rule + templates render SLX/Runbook YAML → assert the rendered YAML has the expected per-tool runtime vars.

- [ ] **Step 1: Add the integration test**

Append to `src/tests.py`:

```python
import os
import tempfile
import yaml as _yaml


class EndToEndMcpIndexingTest(TestCase):
    """Runs the full mcp_tools indexer against an in-memory MCP_CONFIG +
    stub MCP server, then renders the rw-generic-codecollection templates
    against the resulting registry and asserts the SLX + Runbook YAML
    reflect the discovered tool."""

    @responses.activate
    def test_indexer_to_template_render(self):
        # 1. Helm-provided MCP_CONFIG (single server)
        mcp_config = {"servers": [
            {"display_name": "jira",
             "url": "https://jira-mcp.internal/mcp",
             "secret_ref": "jira-mcp-token"},
        ]}

        # 2. Stub MCP tools/list
        url = "https://jira-mcp.internal/mcp"

        def init_cb(request):
            body = json.loads(request.body)
            return (200, {"Content-Type": "application/json",
                          "Mcp-Session-Id": "s1"},
                    json.dumps({"jsonrpc": "2.0", "id": body["id"],
                                "result": {"protocolVersion": "2025-03-26",
                                           "capabilities": {},
                                           "serverInfo": {"name": "x", "version": "0"}}}))

        def list_cb(request):
            body = json.loads(request.body)
            if body.get("method") == "notifications/initialized":
                return (200, {}, "")
            assert body["method"] == "tools/list"
            return (200, {"Content-Type": "application/json"},
                    json.dumps({"jsonrpc": "2.0", "id": body["id"],
                                "result": {"tools": [
                                    {"name": "create_issue",
                                     "description": "Create a Jira issue",
                                     "inputSchema": {
                                         "type": "object",
                                         "properties": {
                                             "project": {"type": "string", "description": "Project key"},
                                             "summary": {"type": "string"},
                                         },
                                         "required": ["project", "summary"]}},
                                ]}}))

        responses.add_callback(responses.POST, url, callback=init_cb)
        responses.add_callback(responses.POST, url, callback=list_cb)
        responses.add_callback(responses.POST, url, callback=list_cb)

        # 3. Run indexer with the secret resolver stubbed out
        ctx = Context({"MCP_CONFIG": mcp_config}, mock.MagicMock())
        ctx.set_property(REGISTRY_PROPERTY_NAME, Registry())
        with mock.patch.object(mcp_tools, "_resolve_secret",
                               return_value="stub-token"):
            mcp_tools.index(ctx)
        reg = ctx.get_property(REGISTRY_PROPERTY_NAME)
        instances = reg.lookup_resource_type("mcp", "mcp_tool").instances
        self.assertEqual(len(instances), 1)
        match_resource = next(iter(instances.values()))

        # 4. Render Runbook template from the codecollection.
        import jinja2
        cb_path = os.environ.get(
            "MCP_TOOL_PROXY_PATH",
            "/Users/prats/Documents/work/rw-generic-codecollection/codebundles/mcp-tool-proxy",
        )
        env = jinja2.Environment(
            loader=jinja2.FileSystemLoader(os.path.join(cb_path, ".runwhen/templates")),
            undefined=jinja2.StrictUndefined,
        )
        t = env.get_template("mcp-tool-proxy-runbook.yaml")
        out = t.render(slx_name="mcp-jira-create-issue",
                       default_location="loc1",
                       match_resource=match_resource)
        parsed = _yaml.safe_load(out)
        runtime_vars = parsed["spec"]["runtimeVarsProvided"]
        names = {v["name"] for v in runtime_vars}
        self.assertEqual(names, {"project", "summary"})
        required_names = {v["name"] for v in runtime_vars if v.get("required") is True}
        self.assertEqual(required_names, {"project", "summary"})
        # Static config var carries the input schema as JSON for the codebundle
        config_names = {c["name"] for c in parsed["spec"]["configProvided"]}
        self.assertEqual(config_names, {"MCP_SERVER_URL", "MCP_TOOL_NAME", "MCP_INPUT_SCHEMA"})
```

- [ ] **Step 2: Run the integration test**

```bash
cd /Users/prats/Documents/work/runwhen-local
PYTHONPATH=src python3 -m pytest src/tests.py::EndToEndMcpIndexingTest -v
```

Expected: 1 passed. If the test can't find the codecollection path on this machine, override with `MCP_TOOL_PROXY_PATH` env var.

- [ ] **Step 3: Commit**

```bash
git add src/tests.py
git commit -m "test(indexer): end-to-end mcp_tools → template render integration test"
```

---

## Phase 6 — Documentation

### Task 6.1: Codebundle README

**Files:**
- Create: `codebundles/mcp-tool-proxy/README.md` (back in `rw-generic-codecollection`)

> **Repo switch back:** `cd /Users/prats/Documents/work/rw-generic-codecollection` and checkout `feat/private-mcp-integration` before this task.

- [ ] **Step 1: Write the README**

Path: `codebundles/mcp-tool-proxy/README.md`

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add codebundles/mcp-tool-proxy/README.md
git commit -m "docs(mcp-tool-proxy): README with architecture, contract, dev guide"
```

---

## Self-Review

### Spec coverage check

Walking spec §7 against the plan:

| Spec section | Plan task(s) |
|---|---|
| §7.1 Architecture (generation side + execution side) | T3.1, T4.5 (gen side); T1.x, T2.x (exec side) |
| §7.2 Data flow (builder cycle + per-invocation) | T4.4 (indexer end-to-end); T2.2 (per-invocation dry-run) |
| §7.3 Drift handling via builder cycle | T4.4 (preserve-on-failure assertion) |
| §7.4 D1 vs D2 discovery | **D2 chosen** — T4.1 (`MCP_CONFIG` setting) + T4.2 (`_load_servers_from_setting`) |
| §7.5.1 `MCPServer` table | **Not needed** — D2 reads from Helm config |
| §7.5.2 papi API surface | **Not needed** — D2 reads from Helm config |
| §7.5.3 `mcp_tool` resource shape | T4.4 (`_emit_tool_resource` matches shape) |
| §7.5.4 Generation rule | T3.1 |
| §7.5.5 SLX template | T3.2 |
| §7.5.6 Runbook template w/ `runtimeVarsProvided` | T3.3 |
| §7.5.7 Robot wrapper + Python script | T1.1–T1.6, T2.1 |
| §7.5.7 footnote: error → failed task; tool output not issue | T1.5 + T1.6 (split: transport/init → fail; tool error → output, exit 0) |
| §7.9 Probe failure → preserve | T4.4 (test asserts) |
| §10.1 D1 vs D2 | Locked: **D2** (plan header) |
| §10.3 SLX naming | Locked: `mcp__{server}__{tool}` (template) |
| §10.5 Probe failure semantics | Locked: preserve (T4.4) |

Papi-side items (§7.5.1, §7.5.2) are **not needed under D2**. UI grouping (§10.10) and per-tool RBAC defaults (§10.11) are deferred for v1.

### Placeholder scan

No "TBD" / "TODO" / "fill in later". One known limitation in T2.2 (Robot dry-run may need a stub for `RW.Core.Import Secret`) is documented inline with a fallback action.

### Type consistency

- Field names in `_emit_tool_resource` (`server_display_name`, `server_url`, `tool_name`, `secret_ref`, `input_schema`) match the template references (`match_resource.spec.server_display_name`, etc.) in T3.2 and T3.3.
- Env-var names (`MCP_SERVER_URL`, `MCP_TOOL_NAME`, `MCP_TOOL_ARGS_JSON`, `MCP_AUTH`, `MCP_INPUT_SCHEMA`) are consistent across Python (T1.6), Robot (T2.1), and templates (T3.2, T3.3).
- The `inputSchema` ↔ `input_schema` translation (MCP wire format uses camelCase, our resource shape uses snake_case) is done in `_emit_tool_resource` (T4.4) so downstream templates see `input_schema` consistently.

---

## Out of scope (deferred)

D2 was chosen, so **no papi or platform-side work is required for v1**. The following items are explicitly NOT in this plan:

1. **Papi `MCPServer` table + CRUD endpoints + registration UI** — not needed for D2. If we later migrate to D1, those land in a separate papi plan.
2. **`helm-charts` repo change** — a one-line addition to the runner Helm chart's values.yaml to expose `mcpConfig.servers` and pass it through to the workspace-builder. Tracked separately; trivial.
3. **Read-only vs. read-write tool classification** — for v1, every generated SLX is tagged `access: read-only` as a safe default. A follow-up will distinguish based on MCP tool annotations (or naming heuristics like `create_*` / `delete_*`).
4. **Per-MCP-server RBAC** — v1 inherits workspace defaults.
5. **UI grouping/filtering** — v1 relies on `additionalContext.path: mcp/{server}` plus the `source=mcp` and `mcp_server={name}` tags rendered by the SLX template.
6. **On-registration UX (immediate builder trigger)** — D2 registration is a Helm upgrade + restart, so the next builder cycle catches it; no special trigger needed.

---

## Execution

Plan complete and saved to `docs/superpowers/plans/2026-05-25-private-mcp-integration.md`. Two execution options:

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints.

Which approach?

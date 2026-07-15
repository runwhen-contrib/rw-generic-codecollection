# Tool-builder / generics-editor contract tests

These tests treat the **user script as a black box** and verify only what the
codebundle *guarantees*:

1. **Input contract** — every runtime var value (quotes, backslashes, newlines,
   shell metacharacters, unicode, empty, very long, JSON-like, …) reaches the
   bash/python script **byte-for-byte** and is injection-safe.
2. **Output contract** — whatever the script returns is ingested, or fails
   **gracefully** (a clear WARNING in the report), never an opaque crash:
   missing issue fields, `main()` returning `None` or a single dict, non-JSON
   output, a bare `EOF` line in the script, non-numeric SLI metrics.

They do **not** test the script's business logic (it can be anything).

## Two tiers

| Tier | File | Needs | What it is |
|------|------|-------|------------|
| Model | `test_tool_builder_contract.py` (+ `harness.py`) | bare `python3` | A harness that mirrors the codebundle's exact steps (real `Evaluate` expressions pulled from the `.robot`, the real `base64 -d`, `subprocess.run(["bash","-c", <heredoc>], env=…)`). Fast, CI-friendly, comprehensive. |
| Integration | `robot_integration/run_real_robot.py` | the **real** RW libraries | Runs the **real** `tool-builder/{runbook,sli}.robot` under Robot Framework using the **actual** `rw-core-keywords` + `rw-cli-keywords` the runner uses — no stubs. They run standalone: user variables come from env vars, issues → `issues.jsonl`, reports → `report.jsonl`, metrics are logged. The gold-standard check. |

## Run

```bash
# model tier (no deps)
python3 tests/contract/test_tool_builder_contract.py      # or: pytest tests/contract

# integration tier (real RunWhen keyword libraries, same as the runner)
pip install -r tests/contract/robot_integration/requirements.txt
python3 tests/contract/robot_integration/run_real_robot.py
```

The integration runner drives inputs the way the runner does — `GEN_CMD`,
`INTERPRETER`, `CONFIG_ENV_MAP`, `SECRET_ENV_MAP`, `CODEBUNDLE_TEMP_DIR`, … as
environment variables — and reads the real `issues.jsonl` / `report.jsonl` back.

## Scope note

Malformed / wrong-type `CONFIG_ENV_MAP` / `SECRET_ENV_MAP` (a non-dict, invalid
JSON) still fail at Suite Setup. That is intentional: papi always emits a valid
JSON dict/list, so it is unreachable in practice — hardening it would belong on
the platform side, not in the codebundle.

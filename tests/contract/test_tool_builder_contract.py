"""Contract tests for the tool-builder / generics-editor SLX codebundle.

The user script is a BLACK BOX — these tests assert only what the codebundle
GUARANTEES: (1) runtime var values reach the script byte-for-byte and safely,
(2) whatever the script returns is ingested or fails *gracefully* (never an
opaque crash). See harness.py for how each step mirrors the real .robot.

Bare python3 (no Robot needed): `python3 tests/contract/test_tool_builder_contract.py`
or pytest. A stronger, real-Robot-Framework integration run lives in
tests/contract/robot_integration/.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import run_case, echo_env_script  # noqa: E402


# ---------- INPUT CONTRACT: every value shape must reach the script intact ----------
INPUT_VALUES = {
    "double_quotes": 'he said "hi" to "you"',
    "single_quotes": "it's a 'test'",
    "backslashes": r"C:\Users\svc  \d+\.\d+",
    "newline_tab": "line1\nline2\tend",
    "shell_injection": "x $(whoami) `id` ${HOME} ; rm -rf / | cat & echo >f",
    "unicode": "café — 日本語 — Ω≈ç — 🚀🔥",
    "empty": "",
    "long_200k": "A" * 200_000,
    "json_like": '{"k":"v","nested":{"a":[1,2,3]},"q":"say \\"hi\\""}',
    "spaces": "   padded   ",
    "sentinel_null": "null",
    "sentinel_none": "None",
    "numeric_str": "007",
    "promql": 'sum(rate(http_requests_total{svc=~"a", code!~"5.."}[5m]))',
}


def _check_input(interpreter, name, value):
    cfg = json.dumps({"TESTVAR": value})
    r = run_case(interpreter, cfg, echo_env_script(interpreter, "TESTVAR"), mode="runbook")
    assert r["ok"], f"{interpreter}/{name}: errored at {r['stage']}: {r.get('error')}"
    assert r.get("probe") == value, f"{interpreter}/{name}: value corrupted in transit"


def test_input_values_reach_bash_intact():
    for name, value in INPUT_VALUES.items():
        _check_input("bash", name, value)


def test_input_values_reach_python_intact():
    for name, value in INPUT_VALUES.items():
        _check_input("python", name, value)


def test_shell_metacharacters_are_not_executed():
    """Injection safety: a value with $(...) / backticks must arrive literally."""
    value = "safe $(touch /tmp/should_not_exist_rwgr67) `whoami`"
    cfg = json.dumps({"TESTVAR": value})
    r = run_case("bash", cfg, echo_env_script("bash", "TESTVAR"), mode="runbook")
    assert r.get("probe") == value
    assert not os.path.exists("/tmp/should_not_exist_rwgr67"), "command substitution executed!"


# ---------- OUTPUT CONTRACT: malformed script output must degrade, not crash ----------
def _issue(**over):
    base = {"issue title": "T", "issue severity": 2, "issue next steps": "n", "issue description": "d"}
    base.update(over)
    return base


def test_wellformed_issues_are_ingested():
    script = f"def main():\n    return [{_issue()!r}, {_issue(**{'issue title': 'U'})!r}]\n"
    r = run_case("python", json.dumps({}), script, mode="runbook")
    assert r["ok"] and len(r["issues"]) == 2


def test_python_main_returns_none_is_graceful():
    r = run_case("python", json.dumps({}), "def main():\n    return None\n", mode="runbook")
    assert r["ok"] and r["issues"] == []


def test_issue_missing_severity_defaults():
    script = "def main():\n    return [{'issue title':'T','issue next steps':'n','issue description':'d'}]\n"
    r = run_case("python", json.dumps({}), script, mode="runbook")
    assert r["ok"] and len(r["issues"]) == 1 and r["issues"][0]["severity"] == 4


def test_issue_missing_title_is_skipped_with_warning():
    script = "def main():\n    return [{'issue severity':2,'issue next steps':'n','issue description':'d'}]\n"
    r = run_case("python", json.dumps({}), script, mode="runbook")
    assert r["ok"] and r["issues"] == []
    assert any("malformed issue" in w for w in r["warnings"])


def test_single_issue_dict_is_normalized_to_a_list():
    script = f"def main():\n    return {_issue(**{'issue title': 'solo'})!r}\n"
    r = run_case("python", json.dumps({}), script, mode="runbook")
    assert r["ok"] and len(r["issues"]) == 1 and r["issues"][0]["title"] == "solo"


def test_non_json_output_is_warned_not_crashed():
    r = run_case("bash", json.dumps({}), 'main() { printf "this is not json" >&3; }\n', mode="runbook")
    assert r["ok"] and r["issues"] == []
    assert any("not valid JSON" in w for w in r["warnings"])


def test_bare_eof_line_in_script_does_not_break_heredoc():
    script = ('main() {\n'
              '  printf \'[{"issue title":"e","issue severity":1,"issue next steps":"n","issue description":"d"}]\' >&3\n'
              '}\nEOF\n')
    r = run_case("bash", json.dumps({}), script, mode="runbook")
    assert r["ok"] and len(r["issues"]) == 1


def test_issue_fields_with_special_chars_preserved():
    special = 'q"u\'o`te $(x)\nnl 🚀'
    script = f"def main():\n    return [{_issue(**{'issue title': special})!r}]\n"
    r = run_case("python", json.dumps({}), script, mode="runbook")
    assert r["ok"] and r["issues"][0]["title"] == special


# ---------- SLI metric contract ----------
def test_sli_numeric_metric():
    r = run_case("python", json.dumps({}), "def main():\n    return 42\n", mode="sli")
    assert r["ok"] and r["metric"] == 42


def test_sli_string_metric_is_coerced():
    r = run_case("python", json.dumps({}), "def main():\n    return '1.5'\n", mode="sli")
    assert r["ok"] and r["metric"] == 1.5


def test_sli_nonnumeric_metric_defaults_to_zero():
    r = run_case("python", json.dumps({}), "def main():\n    return {'v': 1}\n", mode="sli")
    assert r["ok"] and r["metric"] == 0


def test_sli_no_output_is_zero():
    r = run_case("bash", json.dumps({}), "main() { :; }\n", mode="sli")
    assert r["ok"] and r["metric"] == 0


# ---------- Documented platform boundary (papi guarantees a valid JSON dict) ----------
def test_malformed_config_env_map_fails_at_parse():
    """papi always emits a valid JSON dict, so this is unreachable in practice — but
    documents that a malformed CONFIG_ENV_MAP fails at Suite Setup (not silently)."""
    r = run_case("python", "{not valid json", "def main():\n    return []\n", mode="runbook")
    assert not r["ok"] and r["stage"].startswith("parse")


if __name__ == "__main__":
    fails = 0
    for _name, _fn in sorted(globals().items()):
        if _name.startswith("test_") and callable(_fn):
            try:
                _fn()
                print(f"PASS  {_name}")
            except AssertionError as exc:
                fails += 1
                print(f"FAIL  {_name}: {exc}")
    raise SystemExit(1 if fails else 0)

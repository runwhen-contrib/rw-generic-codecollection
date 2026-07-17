"""Regression tests for runbook.robot's Suite Initialization Evaluate calls.

The robot suite parses MCP_INPUT_SCHEMA (a JSON-string env var) inside an
`Evaluate` keyword. Robot Framework offers two ways to reference a variable
inside an Evaluate expression:

  - `${var}`  — the value is substituted into the expression as SOURCE TEXT
                (Python then re-parses any backslash escapes inside it).
  - `$var`    — the value is passed to the expression's namespace as a Python
                OBJECT (no source-level substitution).

The original suite used `'''${schema_json}'''`, which broke whenever a tool
description contained an escaped quote like `\"me\"`: Python's triple-quoted
string-literal parser turned `\"` back into `"`, corrupting the JSON before
`json.loads` ever saw it. The fix is to use `$schema_json` instead.

These tests pin that behavior so we don't regress, without needing to spin
up a real Robot suite (RW.Core only ships in the runner image).
"""
import json


# Pulled verbatim from the failing Linear `list_issues` schema reported by
# the runner — has multiple `\"me\"`-style escapes scattered through the
# property descriptions. If we ever regress, this is the smoking gun.
LINEAR_SCHEMA = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "assignee": {
            "anyOf": [{"type": "string"}, {"type": "null"}],
            "description": 'User ID, name, email, or "me"',
        },
        "delegate": {
            "type": "string",
            "description": (
                'Agent name or ID. When the user asks to delegate to "Linear" '
                'or "the Linear agent", this refers to the "Linear" app user '
                "specifically"
            ),
        },
    },
}


def _evaluate_source_interp(schema_json: str):
    """Simulate Robot's old `'''${schema_json}'''` interpolation: substitute
    the value into the expression text, then `eval`. This is what produced
    the JSONDecodeError in production."""
    expr = f"json.loads('''{schema_json}''') if '''{schema_json}''' else {{}}"
    return eval(expr, {"json": json})


def _evaluate_object_pass(schema_json: str):
    """Simulate Robot's new `$schema_json` form: bind the value to the
    expression's namespace as a Python object, no source substitution."""
    expr = "json.loads(schema_json) if schema_json else {}"
    return eval(expr, {"json": json, "schema_json": schema_json})


def test_quoted_word_in_description_breaks_source_interpolation():
    schema_json = json.dumps(LINEAR_SCHEMA)
    try:
        _evaluate_source_interp(schema_json)
    except json.JSONDecodeError:
        return
    raise AssertionError(
        "source-text interpolation unexpectedly succeeded; the bug we're "
        "regression-testing against is no longer reproducible — re-check "
        "the runbook.robot Evaluate calls."
    )


def test_quoted_word_in_description_survives_object_pass():
    schema_json = json.dumps(LINEAR_SCHEMA)
    parsed = _evaluate_object_pass(schema_json)
    assignee_desc = parsed["properties"]["assignee"]["description"]
    assert assignee_desc == 'User ID, name, email, or "me"'
    delegate_desc = parsed["properties"]["delegate"]["description"]
    assert '"Linear"' in delegate_desc


def test_empty_schema_returns_empty_dict():
    # Robot's default for MCP_INPUT_SCHEMA is "{}", but the conditional
    # also needs to behave when the variable is empty-string. Both must
    # land on an empty dict, not crash.
    assert _evaluate_object_pass("") == {}
    assert _evaluate_object_pass("{}") == {}


def test_runbook_uses_dollar_var_syntax():
    """Static guard: the runbook should not use `'''${var}'''` inside any
    executable line — that's the exact construct the bug rode in on. Ignores
    comment lines so the cautionary note in the source itself doesn't trip
    the check."""
    import pathlib
    runbook = pathlib.Path(__file__).resolve().parent.parent / "runbook.robot"
    forbidden = "'''${"
    offenders = []
    for lineno, raw in enumerate(runbook.read_text().splitlines(), start=1):
        stripped = raw.lstrip()
        if stripped.startswith("#"):
            continue
        if forbidden in raw:
            offenders.append(f"  line {lineno}: {raw.rstrip()}")
    assert not offenders, (
        f"runbook.robot uses {forbidden!r} on executable lines:\n"
        + "\n".join(offenders)
        + "\nRobot substitutes ${var} as source text and Python re-parses "
        "backslash escapes inside the triple-quoted string, corrupting any "
        "embedded JSON. Use `$var` (no curly braces) to pass the value as "
        "a Python object instead."
    )

"""Regression test: complex JSON runtime vars must survive the generics-editor /
tool-builder Suite Initialization ``Evaluate`` expressions.

Background
----------
A custom task whose runtime var value contains double quotes (e.g. a PromQL
``QUERY``) failed on the runner with::

    Parent suite setup failed:
    Evaluating expression 'json.loads('{... "QUERY": "...service=~\\"...\\"..."}' if ...)'
    failed: JSONDecodeError: Expecting ',' delimiter: line 1 column N (char N-1)

Root cause: the codebundle embedded the runtime-vars JSON blob into a Robot
``Evaluate`` expression using ``'${var}'`` -- a **single-quoted, non-raw** Python
string literal. Robot substitutes the variable's text into the expression SOURCE,
so Python then un-escapes the JSON's ``\\"`` back to ``"`` and corrupts the JSON
before ``json.loads`` runs.

This test reads the ACTUAL ``.robot`` files, extracts the real ``Evaluate``
expressions, and runs them under a faithful model of Robot's two substitution
modes:

* ``${var}``  -> text substitution into the expression source (the buggy form)
* ``$var``    -> the variable is passed as a Python object into the eval
                 namespace (the fix)

Run standalone (no deps):  ``python3 tests/test_runtime_var_escaping.py``
Or with pytest:            ``pytest tests/test_runtime_var_escaping.py``
"""

import json
import os
import re

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# A synthetic PromQL query whose value contains double quotes -- the shape that
# triggered the bug. No real hostnames/identifiers.
SAMPLE_QUERY = (
    'sum by (path) (http_requests_total'
    '{service=~"example-service", pod=~".*", status!~"5.."})'
)
SAMPLE_CONFIG = {
    "BASE_URL": "https://api.example.com",
    "CLIENT_ID": "example-client",
    "SCOPES": "example-scope",
    "AUTHORITY": "https://auth.example.com",
    "QUERY": SAMPLE_QUERY,
}
SECRET_NAMES = ["GITHUB_TOKEN", "DB_PASSWORD"]

# The four codebundle robot files that share the runtime-var parsing pattern.
ROBOT_FILES = [
    "codebundles/generics-editor/runbook.robot",
    "codebundles/generics-editor/sli.robot",
    "codebundles/tool-builder/runbook.robot",
    "codebundles/tool-builder/sli.robot",
]


def _extract_evaluate_expression(robot_path, robot_var_name):
    """Return the Python expression Robot's Evaluate would run for the line whose
    expression references ``${robot_var_name}`` or ``$robot_var_name``.

    A codebundle line looks like::

        ${raw_env_vars}=    Evaluate    <EXPRESSION>    modules=json
    """
    with open(robot_path, encoding="utf-8") as fh:
        for raw_line in fh:
            if "Evaluate" not in raw_line or robot_var_name not in raw_line:
                continue
            # Robot cells are separated by runs of >=2 spaces.
            cells = re.split(r" {2,}|\t", raw_line.strip())
            # cells: ['${raw_env_vars}=', 'Evaluate', '<EXPRESSION>', 'modules=json']
            try:
                idx = cells.index("Evaluate")
            except ValueError:
                continue
            expr = cells[idx + 1]
            return expr
    raise AssertionError(
        f"No Evaluate line referencing {robot_var_name!r} found in {robot_path}"
    )


def _robot_evaluate(expr, var_name, value):
    """Faithfully emulate Robot Framework's ``Evaluate`` for a single variable.

    * ``$var``    -> value bound as a Python object in the eval namespace.
    * ``${var}``  -> value's text spliced into the expression source verbatim.
    """
    ns = {"json": json}
    object_ref = re.search(r"\$" + re.escape(var_name) + r"\b", expr)
    braced_ref = "${" + var_name + "}"
    if object_ref and braced_ref not in expr:
        # Object form: Robot exposes the variable by name in the namespace.
        py = re.sub(r"\$" + re.escape(var_name) + r"\b", var_name, expr)
        return eval(py, ns, {var_name: value})  # noqa: S307 - test harness
    # Text-substitution form: Robot splices the raw value into the source.
    py = expr.replace(braced_ref, value)
    return eval(py, ns, {})  # noqa: S307 - test harness


def test_env_vars_json_roundtrips_quote_bearing_query():
    """CONFIG_ENV_MAP with a quote-bearing value must json.loads intact on the runner."""
    config_json = json.dumps(SAMPLE_CONFIG)  # what papi stores (valid JSON, quotes escaped)
    for rel in ROBOT_FILES:
        path = os.path.join(REPO_ROOT, rel)
        expr = _extract_evaluate_expression(path, "env_vars_json")
        result = _robot_evaluate(expr, "env_vars_json", config_json)
        assert result == SAMPLE_CONFIG, f"{rel}: env vars did not round-trip"
        assert result["QUERY"] == SAMPLE_QUERY, f"{rel}: QUERY corrupted"


def test_secret_names_json_roundtrips():
    """SECRET_ENV_MAP list must json.loads intact (consistency fix, same pattern)."""
    secrets_json = json.dumps(SECRET_NAMES)
    for rel in ROBOT_FILES:
        path = os.path.join(REPO_ROOT, rel)
        expr = _extract_evaluate_expression(path, "secrets_json")
        result = _robot_evaluate(expr, "secrets_json", secrets_json)
        assert result == SECRET_NAMES, f"{rel}: secret names did not round-trip"


def test_empty_and_sentinel_values_default_safely():
    """Empty / 'null' / 'None' sentinels must still fall back to an empty container."""
    for rel in ROBOT_FILES:
        path = os.path.join(REPO_ROOT, rel)
        env_expr = _extract_evaluate_expression(path, "env_vars_json")
        sec_expr = _extract_evaluate_expression(path, "secrets_json")
        for sentinel in ("", "null", "None"):
            assert _robot_evaluate(env_expr, "env_vars_json", sentinel) == {}, (
                f"{rel}: env sentinel {sentinel!r} should default to {{}}"
            )
            assert _robot_evaluate(sec_expr, "secrets_json", sentinel) == [], (
                f"{rel}: secret sentinel {sentinel!r} should default to []"
            )


if __name__ == "__main__":
    failures = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"PASS  {name}")
            except AssertionError as exc:
                failures += 1
                print(f"FAIL  {name}: {exc}")
            except Exception as exc:  # noqa: BLE001 - surface the real runner error
                failures += 1
                print(f"ERROR {name}: {type(exc).__name__}: {exc}")
    raise SystemExit(1 if failures else 0)

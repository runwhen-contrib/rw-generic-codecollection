"""Last-mile test: once CONFIG_ENV_MAP is parsed (the json.loads fix), do the
runtime var values actually reach the user's bash/python script intact?

The codebundle Task (generics-editor/tool-builder runbook.robot) runs the user
script via::

    ${rsp}=    RW.CLI.Run Cli    cmd=${command}    env=${raw_env_vars}    ...

With no ``service=``, ``RW.CLI`` routes to ``execute_local_command`` which does
(``rw-cli-codecollection/libraries/RW/CLI/local_process.py``)::

    run_with_env.update(env)                                   # line 86
    final_env = {k: str(v) for k, v in run_with_env.items()}   # line 136
    parsed_cmd = ["bash", "-c", cmd]                           # line 149
    subprocess.run(parsed_cmd, env=final_env, ...)             # line 157-164

i.e. the values are handed to the child as a real **process environment** (execve),
never spliced into a shell string. This test reproduces that exact mechanism and
proves a quote-bearing PromQL QUERY (and worse) reaches both a bash and a python
``main()`` byte-for-byte -- and is injection-safe.

Run:  python3 tests/test_env_reaches_script.py   (or via pytest)
"""

import json
import os
import subprocess

# Synthetic values only -- no real hostnames/identifiers.
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
# A value crafted to break ANY string-interpolation approach: double + single
# quotes, backticks, $(...) and ${...} expansions, and a backslash.
HOSTILE_VALUE = """a"b'c`d$(whoami)e${HOME}f\\g"""


def _run_like_codebundle(interpreter, user_script, env_vars):
    """Mirror execute_local_command: pass env as a dict to subprocess, run the
    heredoc exactly as the codebundle Task builds it."""
    # Suite Init also merges these two before running (runbook.robot:126-127).
    raw_env_vars = dict(env_vars)
    raw_env_vars.setdefault("SSL_CERT_FILE", "/etc/ssl/certs/ca-certificates.crt")
    # local_process.py:136 stringifies values; keep real os.environ so bash has PATH.
    final_env = dict(os.environ)
    final_env.update({k: str(v) for k, v in raw_env_vars.items() if v is not None})

    # local_process.py:149 -> parsed_cmd = ["bash", "-c", cmd]; the codebundle's
    # cmd is a quoted heredoc piping the user script into bash/python.
    cmd = f"{interpreter} << 'EOF'\n{user_script}\nmain\nEOF" if interpreter == "bash" \
        else f"{interpreter} << 'EOF'\n{user_script}\nmain()\nEOF"
    return subprocess.run(
        ["bash", "-c", cmd], text=True, capture_output=True, env=final_env, timeout=30
    )


def test_bash_script_receives_exact_query():
    raw_env_vars = json.loads(json.dumps(SAMPLE_CONFIG))  # what the fixed codebundle produces
    user_script = 'main() { printf "QUERY=[%s]\\n" "$QUERY"; printf "AUTH=[%s]\\n" "$AUTHORITY"; }'
    p = _run_like_codebundle("bash", user_script, raw_env_vars)
    assert p.returncode == 0, p.stderr
    assert f"QUERY=[{SAMPLE_QUERY}]" in p.stdout, p.stdout
    assert f"AUTH=[{SAMPLE_CONFIG['AUTHORITY']}]" in p.stdout, p.stdout


def test_python_script_receives_exact_query():
    raw_env_vars = json.loads(json.dumps(SAMPLE_CONFIG))
    user_script = (
        "import os\n"
        "def main():\n"
        '    print("QUERY=[" + os.environ["QUERY"] + "]")\n'
    )
    p = _run_like_codebundle("python3", user_script, raw_env_vars)
    assert p.returncode == 0, p.stderr
    assert f"QUERY=[{SAMPLE_QUERY}]" in p.stdout, p.stdout


def test_hostile_value_passes_literally_and_is_injection_safe():
    """A value with quotes/backticks/$() must arrive verbatim, with no shell
    evaluation (env values are not re-scanned by bash)."""
    raw_env_vars = json.loads(json.dumps({"EVIL": HOSTILE_VALUE}))
    user_script = 'main() { printf "EVIL=[%s]\\n" "$EVIL"; }'
    p = _run_like_codebundle("bash", user_script, raw_env_vars)
    assert p.returncode == 0, p.stderr
    assert f"EVIL=[{HOSTILE_VALUE}]" in p.stdout, p.stdout
    # $(whoami) must NOT have executed:
    assert "$(whoami)" in p.stdout, "command substitution leaked — value was not literal"


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
            except Exception as exc:  # noqa: BLE001
                failures += 1
                print(f"ERROR {name}: {type(exc).__name__}: {exc}")
    raise SystemExit(1 if failures else 0)

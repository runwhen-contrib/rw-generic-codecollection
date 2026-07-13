"""Real-library contract check: run the ACTUAL tool-builder .robot under Robot
Framework using the REAL RunWhen keyword libraries the runner uses — NO stubs.

    pip install -r tests/contract/robot_integration/requirements.txt

RW.Core (Import User Variable / Add Issue / Push Metric / Add Pre To Report) and
RW.CLI (Run Cli) run standalone the same way they do on the runner:
  * user variables are read from environment variables (os.getenv),
  * issues -> <outputdir>/issues.jsonl, reports -> report.jsonl,
  * metrics are logged ("Metric value=…"); the OTel push is skipped without RW_LOCATION.
We drive inputs via env and read those real outputs back.

Run:  python3 tests/contract/robot_integration/run_real_robot.py
"""
import base64
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
CB = os.path.join(REPO, "codebundles", "tool-builder")

try:
    import RW.Core  # noqa: F401
    import RW.CLI   # noqa: F401
except Exception:  # noqa: BLE001
    print("SKIP: real RW libraries not installed. Run:\n"
          f"  pip install -r {os.path.join(HERE, 'requirements.txt')}")
    raise SystemExit(0)

ROBOT = shutil.which("robot") or os.path.join(os.path.dirname(sys.executable), "robot")

# The runner image ships a working `python`; locally it may be an unconfigured
# shim, so point `python` at this interpreter for the heredoc.
SHIM = tempfile.mkdtemp(prefix="pyshim_")
os.symlink(sys.executable, os.path.join(SHIM, "python"))


def run(robot_name, script, interpreter="python", run_type="runbook", config="{}", secrets="[]"):
    out = tempfile.mkdtemp(prefix="rb_")
    env = dict(os.environ)
    env.update({
        "PATH": SHIM + os.pathsep + env.get("PATH", ""),
        "CODEBUNDLE_TEMP_DIR": out,           # runner sets this; RW.CLI forwards it into env
        "GEN_CMD": base64.b64encode(script.encode()).decode(),
        "INTERPRETER": interpreter,
        "RUN_TYPE": run_type,
        "TASK_TITLE": "dev-test",
        "TIMEOUT_SECONDS": "30",
        "CONFIG_ENV_MAP": config,
        "SECRET_ENV_MAP": secrets,
    })
    # DEBUG loglevel so RW.Core.Push Metric's "Metric value=…" debug_log lands in output.xml.
    p = subprocess.run([ROBOT, "--loglevel", "DEBUG", "--outputdir", out,
                        os.path.join(CB, robot_name + ".robot")],
                       env=env, capture_output=True, text=True, timeout=120)
    issues = _read_jsonl(os.path.join(out, "issues.jsonl"))
    warnings = [json.dumps(r) for r in _read_jsonl(os.path.join(out, "report.jsonl"))
                if "WARNING" in json.dumps(r)]
    xml = os.path.join(out, "output.xml")
    log_text = open(xml, encoding="utf-8").read() if os.path.exists(xml) else ""
    metrics = re.findall(r"Metric value=([0-9.eE+-]+)", log_text + p.stdout + p.stderr)
    shutil.rmtree(out, ignore_errors=True)
    return {"rc": p.returncode, "issues": issues, "warnings": warnings, "metrics": metrics,
            "log": log_text + p.stdout + p.stderr}


def _read_jsonl(path):
    if not os.path.exists(path):
        return []
    rows = []
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if line:
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return rows


def _sev(issue):
    for k in ("severity", "issue severity", "severity_level"):
        if k in issue:
            return issue[k]
    return None


def _title(issue):
    for k in ("title", "issue title"):
        if k in issue:
            return issue[k]
    return None


CASES, fails = [], 0


def check(cid, desc, cond, r):
    global fails
    ok = bool(cond)
    fails += 0 if ok else 1
    CASES.append((cid, "PASS" if ok else "FAIL", desc, r))


ISSUE = '{"issue title":"T","issue severity":2,"issue next steps":"n","issue description":"d"}'
try:
    r = run("runbook", f"def main():\n    return [{ISSUE}]\n")
    check("E1", "well-formed issue -> real Add Issue", r["rc"] == 0 and len(r["issues"]) == 1 and _sev(r["issues"][0]) == 2, r)

    r = run("runbook", "def main():\n    return None\n")
    check("D5", "main() None -> FAILS loudly", r["rc"] != 0 and "did not return a JSON list" in r["log"], r)

    r = run("runbook", 'def main():\n    return [{"issue title":"T","issue next steps":"n","issue description":"d"}]\n')
    check("E3", "missing severity -> default 4 (task passes)", r["rc"] == 0 and len(r["issues"]) == 1 and _sev(r["issues"][0]) == 4, r)

    r = run("runbook", 'def main():\n    return [{"issue severity":2,"issue next steps":"n","issue description":"d"}]\n')
    check("E4", "missing title -> FAILS loudly", r["rc"] != 0 and "malformed issue" in r["log"], r)

    r = run("runbook", f"def main():\n    return {ISSUE}\n")
    check("E7", "single dict return -> FAILS loudly", r["rc"] != 0 and "did not return a JSON list" in r["log"], r)

    r = run("runbook", 'main() { printf "not json" >&3; }\n', interpreter="bash")
    check("E8", "non-JSON output -> FAILS loudly", r["rc"] != 0 and "could not be read as JSON" in r["log"], r)

    r = run("runbook", f'def main():\n    return [{ISSUE}, {{"issue severity":2}}]\n')
    check("E4b", "valid issue recorded, then FAILS on malformed one", r["rc"] != 0 and len(r["issues"]) == 1, r)

    r = run("runbook", 'main() {\n  printf \'[%s]\' \'' + ISSUE + '\' >&3\n}\nEOF\n', interpreter="bash")
    check("D6", "bare EOF line no longer breaks", r["rc"] == 0 and len(r["issues"]) == 1, r)

    r = run("runbook", 'def main():\n    return [{"issue title":"T","issue severity":99,"issue next steps":"n","issue description":"d"}]\n')
    check("E5", "severity 99 -> real Add Issue coerces to 4", r["rc"] == 0 and len(r["issues"]) == 1 and _sev(r["issues"][0]) == 4, r)

    r = run("sli", "def main():\n    return '1.5'\n", run_type="sli")
    check("E10", "sli string metric coerced to 1.5", r["rc"] == 0 and any(abs(float(m) - 1.5) < 1e-9 for m in r["metrics"]), r)

    r = run("sli", "def main():\n    return {'v':1}\n", run_type="sli")
    check("E11", "sli dict metric -> 0", r["rc"] == 0 and any(float(m) == 0 for m in r["metrics"]), r)
finally:
    shutil.rmtree(SHIM, ignore_errors=True)

print(f"\n{'ID':<5} {'RESULT':<6} DESCRIPTION")
print("-" * 62)
for cid, res, desc, r in CASES:
    print(f"{cid:<5} {res:<6} {desc}")
    if res == "FAIL":
        print(f"      rc={r['rc']} issues={r['issues']} metrics={r['metrics']} warnings={r['warnings']}")
print(f"\n{sum(1 for c in CASES if c[1] == 'PASS')}/{len(CASES)} passed  (real rw-core-keywords + rw-cli-keywords)")
raise SystemExit(1 if fails else 0)

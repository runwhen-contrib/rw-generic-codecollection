"""Gold-standard contract check: run the REAL tool-builder .robot under Robot
Framework with stub RW.Core/RW.CLI/RW.platform libraries (RW/ next to this file),
driving inputs via env vars. Confirms the codebundle handles the reachable
failure modes gracefully (no opaque crash).

Requires Robot Framework:  pip install robotframework
Run:                       python3 tests/contract/robot_integration/run_real_robot.py

Uses a stub RW layer only for the platform boundary (Import User Variable/Secret,
Run Cli, Add Issue, Push Metric); the codebundle's own runbook.robot / sli.robot
logic runs for real.
"""
import base64
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))  # tests/contract/robot_integration
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))  # repo root (up 3)
CB = os.path.join(REPO, "codebundles", "tool-builder")

if shutil.which("robot") is None and not os.path.exists(sys.prefix + "/bin/robot"):
    print("SKIP: Robot Framework not installed (pip install robotframework)")
    raise SystemExit(0)
ROBOT = shutil.which("robot") or (sys.prefix + "/bin/robot")

# The runner image ships a working `python`; locally it may be an unconfigured
# shim, so point `python` at this interpreter for the heredoc.
SHIM = tempfile.mkdtemp(prefix="pyshim_")
os.symlink(sys.executable, os.path.join(SHIM, "python"))


def run(robot_name, script, interpreter="python", run_type="runbook", config=None):
    tmp = tempfile.mkdtemp(prefix="rb_")
    results = os.path.join(tmp, "results.jsonl")
    env = dict(os.environ)
    env.update({
        "PATH": SHIM + os.pathsep + env.get("PATH", ""),
        "PYTHONPATH": HERE + os.pathsep + env.get("PYTHONPATH", ""),
        "CODEBUNDLE_TEMP_DIR": tmp,
        "RW_RESULTS_FILE": results,
        "RWVAR_GEN_CMD": base64.b64encode(script.encode()).decode(),
        "RWVAR_INTERPRETER": interpreter,
        "RWVAR_RUN_TYPE": run_type,
        "RWVAR_TASK_TITLE": "dev-test",
        "RWVAR_TIMEOUT_SECONDS": "30",
    })
    if config is not None:
        env["RWVAR_CONFIG_ENV_MAP"] = config
    p = subprocess.run([ROBOT, "--outputdir", tmp, os.path.join(CB, robot_name + ".robot")],
                       env=env, capture_output=True, text=True, timeout=120)
    recs = [json.loads(l) for l in open(results)] if os.path.exists(results) else []
    return {
        "rc": p.returncode,
        "issues": [r for r in recs if r["type"] == "issue"],
        "metrics": [r for r in recs if r["type"] == "metric"],
        "warnings": [r["msg"] for r in recs if r["type"] == "report" and "WARNING" in r["msg"]],
    }


CASES, fails = [], 0


def check(cid, desc, cond, r):
    global fails
    ok = bool(cond)
    fails += 0 if ok else 1
    CASES.append((cid, "PASS" if ok else "FAIL", desc, r))


ISSUE = '{"issue title":"T","issue severity":2,"issue next steps":"n","issue description":"d"}'
try:
    r = run("runbook", f"def main():\n    return [{ISSUE}]\n")
    check("E1", "well-formed issue works", r["rc"] == 0 and len(r["issues"]) == 1, r)
    r = run("runbook", "def main():\n    return None\n")
    check("D5", "main() returns None -> graceful", r["rc"] == 0 and not r["issues"], r)
    r = run("runbook", 'def main():\n    return [{"issue title":"T","issue next steps":"n","issue description":"d"}]\n')
    check("E3", "missing severity -> default 4", r["rc"] == 0 and str(r["issues"][0]["severity"]) == "4", r)
    r = run("runbook", 'def main():\n    return [{"issue severity":2,"issue next steps":"n","issue description":"d"}]\n')
    check("E4", "missing title -> skipped+warned", r["rc"] == 0 and not r["issues"] and any("malformed" in w for w in r["warnings"]), r)
    r = run("runbook", f"def main():\n    return {ISSUE}\n")
    check("E7", "single dict normalized", r["rc"] == 0 and len(r["issues"]) == 1, r)
    r = run("runbook", 'main() { printf "not json" >&3; }\n', interpreter="bash")
    check("E8", "non-JSON output -> warned", r["rc"] == 0 and any("not valid JSON" in w for w in r["warnings"]), r)
    r = run("runbook", 'main() {\n  printf \'[%s]\' \'' + ISSUE + '\' >&3\n}\nEOF\n', interpreter="bash")
    check("D6", "bare EOF line no longer breaks", r["rc"] == 0 and len(r["issues"]) == 1, r)
    r = run("sli", "def main():\n    return '1.5'\n", run_type="sli")
    check("E10", "sli string metric coerced", r["rc"] == 0 and any(float(m["value"]) == 1.5 for m in r["metrics"]), r)
    r = run("sli", "def main():\n    return {'v':1}\n", run_type="sli")
    check("E11", "sli dict metric -> 0", r["rc"] == 0 and any(float(m["value"]) == 0 for m in r["metrics"]), r)
finally:
    shutil.rmtree(SHIM, ignore_errors=True)

print(f"\n{'ID':<5} {'RESULT':<6} DESCRIPTION")
print("-" * 60)
for cid, res, desc, r in CASES:
    print(f"{cid:<5} {res:<6} {desc}")
    if res == "FAIL":
        print(f"      rc={r['rc']} issues={r['issues']} metrics={r['metrics']} warnings={r['warnings']}")
print(f"\n{sum(1 for c in CASES if c[1] == 'PASS')}/{len(CASES)} passed")
raise SystemExit(1 if fails else 0)

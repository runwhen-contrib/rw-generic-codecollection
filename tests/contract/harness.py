"""Contract test harness for the tool-builder SLX codebundle.

Treats the user script as a BLACK BOX. Reproduces exactly the codebundle's
contract-relevant steps (mirrored to codebundles/tool-builder/{runbook,sli}.robot),
so we can test what the codebundle GUARANTEES regardless of what the script does:

  platform inputs -> [parse CONFIG_ENV_MAP] -> [decode GEN_CMD] -> [heredoc exec
  with env] -> script -> [read output file] -> [extract issues / metric]

Fidelity notes (line refs = codebundles/tool-builder/runbook.robot unless noted):
  * parse step uses the REAL Evaluate expression pulled from the .robot (:115).
  * output read uses the REAL Evaluate expression from the .robot (:61 / sli :59).
  * GEN_CMD decode runs the REAL `echo '<b64>' | base64 -d` (:29) via a subshell.
  * execution mirrors RW.CLI -> execute_local_command:
      subprocess.run(["bash","-c", <heredoc>], env=<dict>)   (local_process.py:149,157)
  * issue extraction mirrors the FOR loop (:68-77): direct ['issue title'] etc.
  * 'python' is mapped to python3 locally (runner uses 'python').

NOT covered (outside the codebundle contract): RW.Core.Add Issue severity
validation and RW.Core.Push Metric type handling live in RW.Core, not this
codebundle; those are noted where relevant.
"""

import base64
import json
import os
import re
import shutil
import subprocess
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TB = os.path.join(REPO, "codebundles", "tool-builder")
RUNBOOK = os.path.join(TB, "runbook.robot")
SLI = os.path.join(TB, "sli.robot")

DEFAULT_TIMEOUT = 30


def _extract_expr(robot_path, marker):
    """Pull the real Python expression from an `Evaluate` line mentioning `marker`."""
    with open(robot_path, encoding="utf-8") as fh:
        for line in fh:
            if "Evaluate" in line and marker in line:
                cells = re.split(r" {2,}|\t", line.strip())
                return cells[cells.index("Evaluate") + 1]
    raise AssertionError(f"no Evaluate/{marker} in {robot_path}")


PARSE_EXPR = _extract_expr(RUNBOOK, "env_vars_json")          # json.loads($env_vars_json) if ... else {}
LOAD_EXPR_RB = _extract_expr(RUNBOOK, "run_output_file")      # json.load(open(r'''...''')) ... else []
LOAD_EXPR_SLI = _extract_expr(SLI, "metric_file")            # json.load(open(r'''...''')) ... else 0


def _robot_eval(expr, **names):
    """Emulate Robot Evaluate faithfully for both substitution forms:
      * ${name}  -> TEXT substitution into the expression source (Robot ${var});
                    used by the raw-literal reads r'''${run_output_file}'''.
      * $name    -> the variable bound as a Python OBJECT in the namespace (Robot
                    $var); used by the parse step json.loads($env_vars_json).
    """
    ns = {"json": json, "os": os}
    for k, v in names.items():
        expr = expr.replace("${" + k + "}", str(v))   # braced -> text splice
    for k in set(re.findall(r"\$(\w+)", expr)):        # bare $name -> object
        if k in names:
            ns[k] = names[k]
    py = re.sub(r"\$(\w+)", r"\1", expr)
    return eval(py, ns)  # noqa: S307


def _decode_gen_cmd(script_src):
    """Mirror runbook.robot:28-29 -> `echo '<b64>' | base64 -d`."""
    b64 = base64.b64encode(script_src.encode()).decode()
    p = subprocess.run(
        ["bash", "-c", f"echo '{b64}' | base64 -d"],
        capture_output=True, text=True, timeout=DEFAULT_TIMEOUT,
    )
    return p.stdout, p.returncode, p.stderr


def _build_heredoc(interpreter, decoded_script, mode):
    """Mirror runbook.robot:31-50 / sli.robot:31-50 (python -> python3 locally)."""
    out_name = "run_output.json" if mode == "runbook" else "metric_data.json"
    if interpreter == "python":
        return "\n".join([
            "python3 << 'RW_GENERIC_EOF'",
            decoded_script,
            "import json, os",
            "resp = main()",
            f'path = os.path.join(os.environ["CODEBUNDLE_TEMP_DIR"], "{out_name}")',
            'f = open(path, "w", encoding="utf-8")',
            "json.dump(resp, f)",
            "f.close()",
            "RW_GENERIC_EOF",
        ])
    file_var = "ISSUES_FILE" if mode == "runbook" else "METRIC_FILE"
    return "\n".join([
        "bash << 'RW_GENERIC_EOF'",
        decoded_script,
        f'{file_var}="$CODEBUNDLE_TEMP_DIR/{out_name}"',
        f'exec 3> "${file_var}"',
        "main",
        "exec 3>&-",
        "RW_GENERIC_EOF",
    ])


SECRETS_EXPR = _extract_expr(RUNBOOK, "secrets_json")  # json.loads($secrets_json) if ... else []


def run_case(interpreter, config_env_serialized, script_src, mode="runbook",
             timeout=DEFAULT_TIMEOUT, secret_env_serialized=None, secret_values=None):
    """Run one contract case. `config_env_serialized` is the raw CONFIG_ENV_MAP
    string exactly as the runner would receive it (usually json.dumps of a dict,
    but may be malformed/empty to test the parse contract). Returns a dict result."""
    r = {"stage": None, "ok": False}
    tmp = tempfile.mkdtemp(prefix="cb_")
    try:
        # STEP 1 — parse CONFIG_ENV_MAP (Suite Init, :115)
        try:
            raw_env_vars = _robot_eval(PARSE_EXPR, env_vars_json=config_env_serialized)
        except Exception as e:  # noqa: BLE001
            r.update(stage="parse(suite-setup)", error=f"{type(e).__name__}: {e}")
            return r
        r["parsed_type"] = type(raw_env_vars).__name__
        if not isinstance(raw_env_vars, dict):
            # Suite Init then does `'PATH' in ${raw_env_vars}` + Set To Dictionary (:117-125)
            r.update(stage="post-parse(non-dict)",
                     error=f"CONFIG_ENV_MAP parsed to {type(raw_env_vars).__name__}, "
                           f"not dict; Suite Init `'PATH' in raw_env_vars` / Set To "
                           f"Dictionary would misbehave")
            return r

        # STEP 2 — decode GEN_CMD (:28-29)
        decoded, dec_rc, dec_err = _decode_gen_cmd(script_src)

        # SECRET_ENV_MAP parse (Suite Init :130-134) — object form
        if secret_env_serialized is not None:
            try:
                secret_names = _robot_eval(SECRETS_EXPR, secrets_json=secret_env_serialized)
            except Exception as e:  # noqa: BLE001
                r.update(stage="secret-parse(suite-setup)", error=f"{type(e).__name__}: {e}")
                return r
            r["secret_names_type"] = type(secret_names).__name__

        # STEP 3 — assemble env exactly like execute_local_command
        raw_env_vars.setdefault("CODEBUNDLE_TEMP_DIR", tmp)  # injected-by-ref in real RW.CLI
        final_env = dict(os.environ)
        final_env["CODEBUNDLE_TEMP_DIR"] = tmp
        final_env.update({k: str(v) for k, v in raw_env_vars.items() if v is not None})

        # Secrets delivered as FILES: env[NAME]=path-to-file, script does `cat "$NAME"`
        # (mirrors execute_local_command secret-file handling + secret_file__KEY kwargs).
        for sname, sval in (secret_values or {}).items():
            spath = os.path.join(tmp, sname)
            with open(spath, "w", encoding="utf-8") as fh:
                fh.write(sval)
            final_env[sname] = spath

        # STEP 4 — run the heredoc (:52-56 -> subprocess.run(["bash","-c",cmd], env=))
        cmd = _build_heredoc(interpreter, decoded, mode)
        try:
            p = subprocess.run(["bash", "-c", cmd], env=final_env,
                               capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            r.update(stage="exec", error=f"timed out after {timeout}s (TIMEOUT_SECONDS)")
            return r
        r.update(script_rc=p.returncode, script_stdout=p.stdout[-4000:],
                 script_stderr=p.stderr[-4000:])

        # probe file (input-contract cases write the value they received here)
        probe_path = os.path.join(tmp, "probe.txt")
        if os.path.exists(probe_path):
            with open(probe_path, encoding="utf-8", errors="surrogateescape") as fh:
                r["probe"] = fh.read()

        # STEP 5 — read output; mirror the hardened TRY/EXCEPT around json.load.
        out_file = os.path.join(tmp, "run_output.json" if mode == "runbook" else "metric_data.json")
        load_expr = LOAD_EXPR_RB if mode == "runbook" else LOAD_EXPR_SLI
        r["warnings"] = []
        try:
            output = _robot_eval(load_expr, run_output_file=out_file, metric_file=out_file)
        except Exception as e:  # noqa: BLE001 - mirror EXCEPT AS ${output_err}
            r["warnings"].append(f"output not valid JSON, ignored: {type(e).__name__}")
            output = [] if mode == "runbook" else 0
        r["output_type"] = type(output).__name__

        # STEP 6 — ingest (hardened)
        if mode == "runbook":
            # normalize: list stays; dict -> [dict]; None/other -> [] (+warn for scalars)
            if isinstance(output, list):
                items = output
            elif isinstance(output, dict):
                items = [output]
            else:
                items = []
                if output is not None:
                    r["warnings"].append(f"output not a list of issues (got {type(output).__name__}); ignored")
            issues = []
            for issue in items:
                title = issue.get("issue title") if isinstance(issue, dict) else None
                if title is None:
                    r["warnings"].append("skipped a malformed issue (not a dict or missing 'issue title')")
                    continue
                issues.append({
                    "title": title,
                    "severity": issue.get("issue severity", 4),
                    "next_steps": issue.get("issue next steps", ""),
                    "details": issue.get("issue description", ""),
                    "observed_at": issue.get("issue observed at", None),
                })
            r["issues"] = issues
        else:
            # coerce to a number; non-numeric metric -> 0
            try:
                metric = float(output) if not isinstance(output, bool) else 0
            except (TypeError, ValueError):
                metric = 0
                r["warnings"].append(f"metric not numeric ({type(output).__name__}); set to 0")
            r["metric"] = metric
            r["metric_type"] = type(output).__name__

        r["ok"] = True
        r["stage"] = "complete"
        return r
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---- reusable black-box scripts (the "user" side; contract-neutral) ----

def echo_env_script(interpreter, varname):
    """Script that writes the value it received for `varname` to probe.txt, then
    emits an empty result. Proves the INPUT contract without assuming the script
    can serialize the value."""
    if interpreter == "python":
        return (
            "def main():\n"
            "    import os\n"
            "    d = os.environ.get(%r, '<MISSING>')\n"
            "    open(os.path.join(os.environ['CODEBUNDLE_TEMP_DIR'],'probe.txt'),'w').write(d)\n"
            "    return []\n" % varname
        )
    return (
        'main() {\n'
        '  printf "%%s" "${%s-<MISSING>}" > "$CODEBUNDLE_TEMP_DIR/probe.txt"\n'
        '  printf "[]" >&3\n'
        '}\n' % varname
    )


def dump_all_env_script():
    """Python script that dumps ALL env vars to probe.txt as JSON (for weird-key tests)."""
    return (
        "def main():\n"
        "    import os, json\n"
        "    json.dump(dict(os.environ), open(os.path.join(os.environ['CODEBUNDLE_TEMP_DIR'],'probe.txt'),'w'))\n"
        "    return []\n"
    )

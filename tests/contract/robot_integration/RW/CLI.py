import os, subprocess
class _Resp:
    def __init__(self, stdout, stderr, rc): self.stdout = stdout; self.stderr = stderr; self.returncode = rc
def run_cli(cmd, env=None, timeout_seconds=60, **kwargs):
    e = env if isinstance(env, dict) else {}
    ctd = os.getenv("CODEBUNDLE_TEMP_DIR")
    if ctd and "CODEBUNDLE_TEMP_DIR" not in e:
        e["CODEBUNDLE_TEMP_DIR"] = ctd          # mutate by ref, like real RW.CLI
    final = dict(os.environ)
    final.update({k: str(v) for k, v in e.items() if v is not None})
    for k, v in kwargs.items():
        if k.startswith("secret_file__"):
            name = k[len("secret_file__"):]
            path = os.path.join(final.get("CODEBUNDLE_TEMP_DIR", "/tmp"), name)
            with open(path, "w", encoding="utf-8") as f:
                f.write(getattr(v, "value", str(v)))
            final[name] = path
    try:
        p = subprocess.run(["bash", "-c", cmd], env=final, capture_output=True,
                           text=True, timeout=int(float(timeout_seconds)))
        return _Resp(p.stdout, p.stderr, p.returncode)
    except subprocess.TimeoutExpired:
        return _Resp("", f"timeout after {timeout_seconds}s", -1)
def pop_shell_history():
    return ""

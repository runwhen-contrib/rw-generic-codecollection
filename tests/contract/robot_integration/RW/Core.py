import json, os
_RESULTS = os.environ.get("RW_RESULTS_FILE", "/tmp/rw_results.jsonl")
def _emit(rec):
    with open(_RESULTS, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, default=str) + "\n")
class _Secret:
    def __init__(self, key, value): self.key = key; self.value = value
def import_user_variable(name, type=None, description=None, default=None, pattern=None, example=None):
    v = os.environ.get("RWVAR_" + name)
    return default if v is None else v
def import_secret(name, *a, **k):
    return _Secret(name, os.environ.get("RWSECRET_" + name, ""))
def add_issue(**kwargs):
    _emit({"type": "issue", **kwargs})
def add_pre_to_report(msg):
    _emit({"type": "report", "msg": str(msg)})
def push_metric(value, sub_name=None):
    _emit({"type": "metric", "value": value, "sub_name": sub_name})

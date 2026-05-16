"""Line-buffered stdin → batched POST to PAPI for live pip-log streaming.

Reads pip stdout line-by-line from stdin and echoes it back to stdout (so
upstream `tee` keeps writing pip_install.log).  Buffers lines for up to
BATCH_MAX_SECONDS (500ms) or BATCH_MAX_LINES (20 lines), whichever first,
then POSTs the batch to:

    {papi_url}/api/v1/workspaces/{ws}/author/run/{run_id}/log/append

On EOF (pip exited), flushes any pending lines, then POSTs a final
{"lines": [], "end": true}.  HTTP errors are logged to stderr but never
fail the script — the canonical pip_install.log is still being written by
`tee` upstream, so streaming is best-effort.

Uses stdlib urllib.request (httpx is not in the worker base image).
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request

BATCH_MAX_LINES = 20
BATCH_MAX_SECONDS = 0.5
HTTP_TIMEOUT_SECONDS = 5.0


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--papi-url", required=True, help="e.g. https://papi.example.com")
    p.add_argument("--workspace", required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--token", required=True)
    args = p.parse_args()

    endpoint = (
        f"{args.papi_url.rstrip('/')}"
        f"/api/v1/workspaces/{args.workspace}/author/run/{args.run_id}/log/append"
    )
    auth_header = f"Bearer {args.token}"

    pending: list[str] = []
    last_flush = time.monotonic()

    def flush(end: bool = False) -> None:
        nonlocal pending, last_flush
        body = json.dumps({"lines": pending, "end": end}).encode("utf-8")
        req = urllib.request.Request(
            endpoint,
            data=body,
            method="POST",
            headers={
                "Authorization": auth_header,
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_SECONDS) as _resp:
                pass
        except (urllib.error.URLError, TimeoutError) as e:
            print(f"[pip_log_streamer] post failed: {e}", file=sys.stderr)
        except Exception as e:  # noqa: BLE001 — best-effort streaming
            print(f"[pip_log_streamer] post failed (unexpected): {e}", file=sys.stderr)
        pending = []
        last_flush = time.monotonic()

    for raw in sys.stdin:
        # Echo upstream so `tee` keeps populating pip_install.log
        sys.stdout.write(raw)
        sys.stdout.flush()
        pending.append(raw.rstrip("\n"))
        if (
            len(pending) >= BATCH_MAX_LINES
            or (time.monotonic() - last_flush) >= BATCH_MAX_SECONDS
        ):
            flush()
    # EOF: pip exited — flush remaining + end sentinel
    if pending:
        flush(end=False)
    flush(end=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())

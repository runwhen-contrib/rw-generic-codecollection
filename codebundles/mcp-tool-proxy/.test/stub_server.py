"""Minimal HTTP MCP stub for local dry-runs of the Robot wrapper.
Listens on $PORT (default 18080), accepts initialize/notifications/tools/call,
echoes back a canned text response."""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(length) or b"{}")
        method = body.get("method", "")
        if method == "initialize":
            resp = {"jsonrpc": "2.0", "id": body["id"],
                    "result": {"protocolVersion": "2025-03-26",
                               "capabilities": {},
                               "serverInfo": {"name": "stub", "version": "0"}}}
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Mcp-Session-Id", "stub-session")
            self.end_headers()
            self.wfile.write(json.dumps(resp).encode())
        elif method == "notifications/initialized":
            self.send_response(200)
            self.end_headers()
        elif method == "tools/call":
            args = body["params"].get("arguments", {})
            text = f"stub-ok name={body['params']['name']} args={json.dumps(args)}"
            resp = {"jsonrpc": "2.0", "id": body["id"],
                    "result": {"content": [{"type": "text", "text": text}]}}
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(resp).encode())
        else:
            self.send_response(400)
            self.end_headers()

    def log_message(self, *_args, **_kw):
        return


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "18080"))
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()

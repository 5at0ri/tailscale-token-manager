#!/usr/bin/env python3
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
import subprocess
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

TOKEN_FILE = "/tokens/token_value"
TAILSCALE_DEVICES_URL = "https://api.tailscale.com/api/v2/tailnet/-/devices"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        # Quiet logging
        sys.stderr.write("proxy: " + fmt % args + "\n")

    def _read_token(self):
        try:
            with open(TOKEN_FILE, "r") as f:
                return f.read().strip()
        except Exception:
            return None

    def _fetch_devices(self, token: str):
        req = Request(TAILSCALE_DEVICES_URL)
        req.add_header("Authorization", f"Bearer {token}")
        req.add_header("Accept", "application/json")
        with urlopen(req, timeout=10) as resp:
            body = resp.read()
            code = resp.getcode()
            return code, body

    def do_GET(self):
        if self.path != "/devices":
            self.send_response(404)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"error":"not found"}')
            return

        token = self._read_token()
        if not token:
            self.send_response(503)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"error":"tailscale token unavailable"}')
            return

        try:
            code, body = self._fetch_devices(token)
            # If unauthorized, force-refresh token and retry once
            if code == 401:
                try:
                    subprocess.run(["/usr/local/bin/token-refresh.sh"], check=False, timeout=15)
                except Exception:
                    pass
                # Re-read token and retry
                token = self._read_token() or ""
                if token:
                    try:
                        code, body = self._fetch_devices(token)
                    except HTTPError as e:
                        code = e.code
                        body = e.read() if hasattr(e, 'read') else b''
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body)
        except HTTPError as e:
            body = e.read() if hasattr(e, 'read') else b''
            self.send_response(e.code)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body or json.dumps({"error": str(e)}).encode())
        except URLError as e:
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())


def main():
    port = int(os.environ.get("PROXY_PORT", "1180"))
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"proxy: listening on {port}")
    server.serve_forever()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Serve the `make view` page on this Mac's loopback.

Chrome's Local Network Access protection stops a file:// page from loading the voxl
streams on 127.0.0.1, so the page needs an http://127.0.0.1 origin of its own. This
serves one file and nothing else. It answers only requests for its own host name, so
another web page cannot read it through DNS rebinding (the page holds voxl passwords).

Usage: view-server.py PORT FILE
"""
import http.server
import sys

PORT = int(sys.argv[1])
FILE = sys.argv[2]
HOSTS = {f"127.0.0.1:{PORT}", f"localhost:{PORT}"}


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get("Host") not in HOSTS or self.path.split("?")[0] != "/":
            self.send_error(404)
            return
        try:
            with open(FILE, "rb") as f:
                body = f.read()
        except OSError:
            self.send_error(404, "run make view")
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()

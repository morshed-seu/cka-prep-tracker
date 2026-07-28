#!/usr/bin/env python3
"""A registry that speaks the handshake and then refuses everything with 429.

Just enough of the distribution API to make a real client produce a real
rate-limit failure, so the drill can be run without hammering Docker Hub.
"""
from http.server import BaseHTTPRequestHandler, HTTPServer

BODY = (b'{"errors":[{"code":"TOOMANYREQUESTS",'
        b'"message":"You have reached your pull rate limit. '
        b'You may increase the limit by authenticating and upgrading."}]}')


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.reply()

    def do_HEAD(self):
        self.reply()

    def reply(self):
        if self.path == "/v2/":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", "2")
            self.end_headers()
            self.wfile.write(b"{}")
            return
        self.send_response(429)
        self.send_header("Content-Type", "application/json")
        self.send_header("Retry-After", "3600")
        self.send_header("RateLimit-Limit", "100;w=21600")
        self.send_header("RateLimit-Remaining", "0;w=21600")
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)

    def log_message(self, *args):
        pass


HTTPServer(("127.0.0.1", 5002), Handler).serve_forever()

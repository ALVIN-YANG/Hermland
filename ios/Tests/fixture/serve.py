"""Ephemeral SSH transport fixture. These pages are contracts, not real Agents."""
import base64
import hashlib
import json
import struct
import threading
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def do_GET(self):
        if self.path == "/":
            self.send_response(302)
            self.send_header("Location", "http://localhost:39121/" if Path("/tmp/hermland-fixture-outside").exists() else "/login")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/ws":
            accept = base64.b64encode(hashlib.sha1(
                (self.headers["Sec-WebSocket-Key"] + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()
            ).digest()).decode()
            self.send_response(101)
            self.send_header("Upgrade", "websocket")
            self.send_header("Connection", "Upgrade")
            self.send_header("Sec-WebSocket-Accept", accept)
            self.end_headers()
            header = self.rfile.read(2)
            if len(header) != 2:
                return
            length = header[1] & 127
            if length == 126:
                length = struct.unpack("!H", self.rfile.read(2))[0]
            if length > 1024:
                return
            mask = self.rfile.read(4) if header[1] & 128 else b"\0" * 4
            payload = bytes(value ^ mask[index % 4] for index, value in enumerate(self.rfile.read(length)))
            self.wfile.write(bytes([0x81, len(payload)]) + payload)
            self.wfile.flush()
            return
        if self.path == "/health":
            body = json.dumps({"status": "ok"}).encode()
        elif self.path == "/healthz":
            body = json.dumps({"status": "live", "ok": True}).encode()
        elif self.path == "/close":
            self.protocol_version = "HTTP/1.0"
            self.close_connection = True
            body = b"short-connection-response"
        elif self.path == "/large":
            body = b"x" * 262144
        elif self.path == "/sse":
            body = b"event: status\ndata: ready\n\nevent: status\ndata: done\n\n"
        elif self.path.startswith("/openclaw"):
            body = b"<!doctype html><openclaw-app></openclaw-app>"
        else:
            body = b"<!doctype html><title>Hermes</title>"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


for port in [9000, 9001]:
    threading.Thread(target=ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever, daemon=True).start()
threading.Event().wait()

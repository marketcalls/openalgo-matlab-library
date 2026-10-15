#!/usr/bin/env python3
"""Recording mock of the OpenAlgo REST API for the MATLAB test suite.

Standard library only. Every request outside /__mock__/ is recorded (method,
raw path, decoded path, raw query, query parameters, selected headers and the
raw body text) and answered with the next queued response, or with the
default response when the queue is empty.

Control endpoints (JSON in and out):

    GET  /__mock__/ping       -> {"ok": true, "port": N, "closed_port": M}
    POST /__mock__/reset      clears the queue and the recorded requests
    POST /__mock__/enqueue    body: one response spec, or {"responses": [...]}
    GET  /__mock__/requests   -> {"requests": [...]} in arrival order
    POST /__mock__/shutdown   stops the server

A response spec is an object with optional keys:

    "status": 200             HTTP status (default 200)
    "json": <any JSON value>  body serialized with json.dumps
    "body": "<text>"          raw body text sent verbatim (UTF-8)
    "content_type": "..."     defaults to application/json for "json",
                              text/plain for "body"
    "delay": seconds          sleep before answering (timeout tests)
    "action": "close"         close the connection without any response

The default response is 200 {"status": "success"}.

Start-up writes the ready file (atomically) with two lines: the listening
port and a "closed" port, a socket that is bound but never listens, so a
connection to it is refused. --lifetime makes the server exit on its own
after that many seconds, so a crashed test run cannot leave it behind.
"""

import argparse
import json
import os
import socket
import sys
import threading
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qsl, unquote

DEFAULT_RESPONSE = {"status": 200, "json": {"status": "success"}}
HEADERS = ("content-type", "user-agent", "content-length", "accept")


class State:
    def __init__(self):
        self.lock = threading.Lock()
        self.queue = deque()
        self.requests = []

    def reset(self):
        with self.lock:
            self.queue.clear()
            self.requests = []

    def enqueue(self, specs):
        with self.lock:
            self.queue.extend(specs)

    def record(self, rec):
        with self.lock:
            rec["seq"] = len(self.requests) + 1
            self.requests.append(rec)
            return self.queue.popleft() if self.queue else dict(DEFAULT_RESPONSE)

    def snapshot(self):
        with self.lock:
            return list(self.requests)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "OpenAlgoTestMock/1.0"

    def log_message(self, fmt, *args):
        pass

    def read_body(self):
        te = (self.headers.get("Transfer-Encoding") or "").lower()
        if "chunked" in te:
            chunks = []
            while True:
                line = self.rfile.readline().strip()
                size = int(line.split(b";")[0], 16) if line else 0
                if size == 0:
                    while self.rfile.readline() not in (b"\r\n", b"\n", b""):
                        pass
                    break
                chunks.append(self.rfile.read(size))
                self.rfile.readline()
            return b"".join(chunks)
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length > 0 else b""

    def send_raw(self, status, data, content_type):
        try:
            self.send_response(status)
            if content_type:
                self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Connection", "close")
            self.end_headers()
            if data:
                self.wfile.write(data)
            self.wfile.flush()
        except OSError:
            pass
        self.close_connection = True

    def send_json(self, status, obj):
        self.send_raw(status, json.dumps(obj).encode("utf-8"), "application/json")

    def handle_any(self):
        parts = self.requestline.split(" ")
        target = parts[1] if len(parts) >= 2 else self.path
        raw_path, _, raw_query = target.partition("?")
        body = self.read_body()
        if raw_path.startswith("/__mock__/"):
            return self.handle_control(raw_path, body)

        headers = {}
        for name in HEADERS:
            value = self.headers.get(name)
            if value is not None:
                headers[name.replace("-", "_")] = value
        query = {}
        for key, value in parse_qsl(raw_query, keep_blank_values=True):
            query.setdefault(key, value)
        spec = self.server.state.record({
            "method": self.command,
            "raw_path": raw_path,
            "path": unquote(raw_path),
            "raw_query": raw_query,
            "query": query,
            "headers": headers,
            "body": body.decode("utf-8", errors="replace"),
        })
        self.respond(spec)

    def respond(self, spec):
        delay = float(spec.get("delay") or 0)
        if delay > 0:
            time.sleep(delay)
        if spec.get("action") == "close":
            try:
                self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.close_connection = True
            return
        status = int(spec.get("status", 200))
        if "json" in spec:
            data = json.dumps(spec["json"]).encode("utf-8")
            ctype = spec.get("content_type", "application/json")
        else:
            data = str(spec.get("body", "")).encode("utf-8")
            ctype = spec.get("content_type", "text/plain")
        self.send_raw(status, data, ctype)

    def handle_control(self, path, body):
        state = self.server.state
        cmd = path[len("/__mock__/"):].strip("/")
        payload = None
        if body:
            try:
                payload = json.loads(body.decode("utf-8"))
            except ValueError:
                return self.send_json(400, {"ok": False, "error": "control body is not JSON"})
        if cmd == "ping":
            return self.send_json(200, {"ok": True, "port": self.server.server_address[1],
                                        "closed_port": self.server.closed_port})
        if cmd == "reset":
            state.reset()
            return self.send_json(200, {"ok": True})
        if cmd == "enqueue":
            if isinstance(payload, dict) and "responses" in payload:
                specs = payload["responses"]
            elif isinstance(payload, list):
                specs = payload
            else:
                specs = [payload or {}]
            state.enqueue(specs)
            return self.send_json(200, {"ok": True, "queued": len(specs)})
        if cmd == "requests":
            return self.send_json(200, {"requests": state.snapshot()})
        if cmd == "shutdown":
            self.send_json(200, {"ok": True})
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return None
        return self.send_json(404, {"ok": False, "error": "unknown control command " + cmd})

    do_GET = handle_any
    do_POST = handle_any
    do_PUT = handle_any
    do_DELETE = handle_any
    do_PATCH = handle_any


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = False


def write_atomic(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, path)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--ready-file", default="")
    parser.add_argument("--pid-file", default="")
    parser.add_argument("--lifetime", type=float, default=1800.0)
    args = parser.parse_args()

    server = Server((args.host, args.port), Handler)
    server.state = State()

    # A bound socket that never listens: connecting to it is refused.
    closed = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    closed.bind((args.host, 0))
    server.closed_port = closed.getsockname()[1]

    if args.pid_file:
        write_atomic(args.pid_file, str(os.getpid()))
    port = server.server_address[1]
    if args.ready_file:
        write_atomic(args.ready_file, "%d\n%d\n" % (port, server.closed_port))
    else:
        print(port, server.closed_port, flush=True)

    if args.lifetime > 0:
        timer = threading.Timer(args.lifetime, server.shutdown)
        timer.daemon = True
        timer.start()
    try:
        server.serve_forever(poll_interval=0.1)
    finally:
        server.server_close()
        closed.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

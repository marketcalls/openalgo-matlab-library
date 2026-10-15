#!/usr/bin/env python3
"""Recording mock of the OpenAlgo REST API and strategy webhook for the parity harness.

Every request that is not a control request is recorded (method, path, query
parameters, headers of interest, raw and parsed body) under the scenario that
is current when it arrives, appended to a JSONL log, and answered from the
scenario's response rules.

Control endpoints (all JSON):

    GET  /__control__/ping                 -> {"ok": true, "closed_port": N}
    POST /__control__/scenario             body {"id": "...", "rules": [...]}
                                           makes that scenario current and
                                           replaces the response rules
    GET  /__control__/requests?id=<id>     -> {"id": ..., "requests": [...]}
                                           (add &bare=1 for the bare array)
    POST /__control__/shutdown             stops the server

A rule is an object. Optional matching keys:

    "match": {"method": "GET", "path": "/api/v1/instruments",
              "query": {"exchange": "NFO"}}
        "path" may contain "*" wildcards. All given keys must match.
    "times": N   the rule is used at most N times (default: unlimited)

and response keys:

    "status": 200               HTTP status (default 200)
    "json": <any JSON value>    body serialized with json.dumps
    "body": "<text>"            raw body text sent verbatim (UTF-8)
    "content_type": "..."       defaults to application/json for "json",
                                text/plain for "body"
    "delay": seconds            sleep before answering (timeout scenarios)
    "action": "close"           close the connection without any response

The first rule that matches and still has uses left answers the request. If
no rule matches, the server answers 404 with a JSON error naming the path so
that a missing rule is visible in the diff.

Every response carries "Connection: close" so that each request uses a fresh
connection; this keeps clients from retrying a request on a stale pooled
connection, which would make request counts differ between languages.

Port 0 picks a free port; --port-file receives the chosen port. The server
also holds a second socket that is bound but never listening, and reports
its port as "closed_port": connecting to it is refused, which is how the
runners exercise the connection-error path.
"""

import argparse
import json
import os
import re
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote

HEADERS_OF_INTEREST = ("content-type", "accept", "user-agent", "content-length",
                       "transfer-encoding")


class State:
    def __init__(self, log_path):
        self.lock = threading.Lock()
        self.scenario = None
        self.rules = []
        self.uses = []
        self.records = {}
        self.seq = 0
        self.log_path = log_path
        self.closed_port = None
        if log_path:
            # Start each server run with an empty log.
            open(log_path, "w", encoding="utf-8").close()

    def set_scenario(self, scenario_id, rules):
        with self.lock:
            self.scenario = scenario_id
            self.rules = list(rules or [])
            self.uses = [0] * len(self.rules)
            self.records[scenario_id] = []

    def record(self, rec):
        with self.lock:
            self.seq += 1
            rec["seq"] = self.seq
            rec["scenario"] = self.scenario
            self.records.setdefault(self.scenario, []).append(rec)
            if self.log_path:
                with open(self.log_path, "a", encoding="utf-8") as fh:
                    fh.write(json.dumps(rec, ensure_ascii=False) + "\n")

    def pick_rule(self, method, path, query):
        with self.lock:
            for i, rule in enumerate(self.rules):
                times = rule.get("times")
                if times is not None and self.uses[i] >= times:
                    continue
                if not rule_matches(rule.get("match") or {}, method, path, query):
                    continue
                self.uses[i] += 1
                return rule
            return None


def wildcard(pattern, value):
    regex = "^" + ".*".join(re.escape(p) for p in pattern.split("*")) + "$"
    return re.match(regex, value) is not None


def rule_matches(match, method, path, query):
    if "method" in match and match["method"].upper() != method.upper():
        return False
    if "path" in match and not wildcard(match["path"], path):
        return False
    for key, want in (match.get("query") or {}).items():
        got = query.get(key)
        if not got or got[0] != str(want):
            return False
    return True


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "OpenAlgoParityMock/1.0"

    def log_message(self, fmt, *args):  # keep the console quiet
        if self.server.verbose:
            sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    # Body reading supports Content-Length and chunked transfer encoding.
    def read_body(self):
        te = (self.headers.get("Transfer-Encoding") or "").lower()
        if "chunked" in te:
            chunks = []
            while True:
                line = self.rfile.readline().strip()
                size = int(line.split(b";")[0], 16) if line else 0
                if size == 0:
                    # Consume trailers up to the blank line.
                    while self.rfile.readline() not in (b"\r\n", b"\n", b""):
                        pass
                    break
                chunks.append(self.rfile.read(size))
                self.rfile.readline()
            return b"".join(chunks)
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length > 0 else b""

    def send_json(self, status, obj):
        self.send_raw(status, json.dumps(obj).encode("utf-8"), "application/json")

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
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, OSError):
            pass
        self.close_connection = True

    def handle_any(self):
        state = self.server.state
        # Use the raw request target: http.server collapses a leading "//" in
        # self.path, and urlsplit would read it as a network location.
        parts = self.requestline.split(" ")
        target = parts[1] if len(parts) >= 2 else self.path
        raw_path, _, raw_query = target.partition("?")
        path = unquote(raw_path)
        query = parse_qs(raw_query, keep_blank_values=True)
        body = self.read_body()

        if path.startswith("/__control__"):
            return self.handle_control(path, query, body)

        text = body.decode("utf-8", errors="replace")
        parsed, is_json = None, False
        if body:
            try:
                parsed, is_json = json.loads(text), True
            except ValueError:
                pass
        headers = {}
        for name in HEADERS_OF_INTEREST:
            value = self.headers.get(name)
            if value is not None:
                headers[name] = value
        state.record({
            "method": self.command,
            "path": path,
            "query": query,
            "headers": headers,
            "content_type": self.headers.get("Content-Type"),
            "has_body": bool(body),
            "body_is_json": is_json,
            "body": parsed if is_json else None,
            "body_raw": None if is_json else text,
            "time": time.time(),
        })

        rule = state.pick_rule(self.command, path, query)
        if rule is None:
            return self.send_json(404, {"status": "error",
                                        "message": "mock: no rule for %s %s" % (self.command, path)})
        if rule.get("delay"):
            time.sleep(float(rule["delay"]))
        if rule.get("action") == "close":
            self.close_connection = True
            try:
                self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            return
        status = int(rule.get("status", 200))
        if "json" in rule:
            data = json.dumps(rule["json"]).encode("utf-8")
            ctype = rule.get("content_type", "application/json")
        else:
            data = str(rule.get("body", "")).encode("utf-8")
            ctype = rule.get("content_type", "text/plain; charset=utf-8")
        return self.send_raw(status, data, ctype)

    def handle_control(self, path, query, body):
        state = self.server.state
        if path == "/__control__/ping":
            return self.send_json(200, {"ok": True, "closed_port": state.closed_port})
        if path == "/__control__/scenario" and self.command == "POST":
            spec = json.loads(body.decode("utf-8") or "{}")
            state.set_scenario(spec.get("id"), spec.get("rules"))
            return self.send_json(200, {"ok": True})
        if path == "/__control__/requests":
            sid = (query.get("id") or [None])[0]
            with state.lock:
                recs = list(state.records.get(sid, []))
            if (query.get("bare") or ["0"])[0] == "1":
                return self.send_json(200, recs)
            return self.send_json(200, {"id": sid, "requests": recs})
        if path == "/__control__/shutdown":
            self.send_json(200, {"ok": True})
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return
        return self.send_json(404, {"ok": False, "message": "unknown control path"})

    do_GET = handle_any
    do_POST = handle_any
    do_PUT = handle_any
    do_DELETE = handle_any
    do_PATCH = handle_any


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = False


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--port-file", help="write the chosen port to this file")
    ap.add_argument("--log", help="JSONL file receiving every recorded request")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    state = State(args.log)
    # A bound but non-listening socket: connections to it are refused.
    closed = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    closed.bind((args.host, 0))
    state.closed_port = closed.getsockname()[1]

    httpd = Server((args.host, args.port), Handler)
    httpd.state = state
    httpd.verbose = args.verbose
    port = httpd.server_address[1]
    if args.port_file:
        tmp = args.port_file + ".tmp"
        with open(tmp, "w") as fh:
            fh.write(str(port))
        os.replace(tmp, args.port_file)
    sys.stderr.write("mock server on http://%s:%d (closed port %d)\n"
                     % (args.host, port, state.closed_port))
    try:
        httpd.serve_forever(poll_interval=0.2)
    finally:
        httpd.server_close()
        closed.close()


if __name__ == "__main__":
    main()

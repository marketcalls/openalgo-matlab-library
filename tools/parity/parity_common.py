"""Helpers shared by the Python-side parity scripts: mock server lifecycle and control calls."""

import json
import os
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "out")
SCENARIOS = os.path.join(HERE, "scenarios.json")


def load_scenarios(path=SCENARIOS):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


class MockServer:
    """Start mock_server.py on a free port, or attach to one given by URL."""

    def __init__(self, lang, url=None):
        self.proc = None
        os.makedirs(OUT_DIR, exist_ok=True)
        if url:
            self.base = url.rstrip("/")
        else:
            port_file = os.path.join(OUT_DIR, "mock_port_%s.txt" % lang)
            if os.path.exists(port_file):
                os.remove(port_file)
            self.log = open(os.path.join(OUT_DIR, "mock_server_%s.log" % lang), "w")
            self.proc = subprocess.Popen(
                [sys.executable, os.path.join(HERE, "mock_server.py"), "--port", "0",
                 "--port-file", port_file,
                 "--log", os.path.join(OUT_DIR, "requests_%s.jsonl" % lang)],
                stdout=self.log, stderr=subprocess.STDOUT)
            deadline = time.time() + 20
            while not os.path.exists(port_file):
                if time.time() > deadline or self.proc.poll() is not None:
                    raise RuntimeError("mock server did not start")
                time.sleep(0.05)
            with open(port_file) as fh:
                self.base = "http://127.0.0.1:%s" % fh.read().strip()
        info = self.get("/__control__/ping")
        self.closed_base = "http://127.0.0.1:%d" % info["closed_port"]

    def _call(self, path, data=None):
        req = urllib.request.Request(self.base + path, data=data,
                                     headers={"Content-Type": "application/json"} if data else {})
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))

    def get(self, path):
        return self._call(path)

    def post(self, path, obj):
        return self._call(path, json.dumps(obj).encode("utf-8"))

    def start_scenario(self, scenario):
        self.post("/__control__/scenario", {"id": scenario["id"], "rules": scenario.get("rules") or []})

    def requests_for(self, scenario_id):
        from urllib.parse import quote
        return self.get("/__control__/requests?id=" + quote(scenario_id))["requests"]

    def stop(self):
        if self.proc is not None:
            try:
                self.post("/__control__/shutdown", {})
            except Exception:
                pass
            try:
                self.proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
            self.log.close()


def substitute(value, mock_base, closed_base):
    """Replace the $MOCK and $CLOSED placeholders in constructor arguments."""
    if isinstance(value, str):
        return value.replace("$MOCK", mock_base).replace("$CLOSED", closed_base)
    if isinstance(value, dict):
        return {k: substitute(v, mock_base, closed_base) for k, v in value.items()}
    if isinstance(value, list):
        return [substitute(v, mock_base, closed_base) for v in value]
    return value


def clean_request(rec):
    """Keep the parts of a recorded request that the comparison uses."""
    return {
        "method": rec["method"],
        "path": rec["path"],
        "query": rec["query"],
        "content_type": rec.get("content_type"),
        "has_body": rec.get("has_body"),
        "body_is_json": rec.get("body_is_json"),
        "body": rec.get("body"),
        "body_raw": rec.get("body_raw"),
        "headers": rec.get("headers"),
    }

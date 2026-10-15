#!/usr/bin/env python3
"""
Mock OpenAlgo WebSocket proxy used by the MATLAB feed tests.

It emulates the parts of the real proxy that the client feed talks to:

* {"action": "authenticate", "api_key": ...} answers with an auth success
  message (broker "mockbroker", user "mockuser") when the key matches
  --api-key, else {"type": "auth", "status": "error", ...}.
* {"action": "subscribe", "symbols": [...], "mode": m, "depth": d} answers
  with a subscribe ack and, unless --no-auto-push is given, pushes one
  market_data message per symbol for that mode (fixed sample values).
* Acks carry the mode as a label ("LTP", "Quote", "Depth") like the real
  proxy. A Depth subscribe with "depth" above 20 is refused per symbol with
  "Depth level N is not supported by this broker"; other levels push N book
  levels.
* {"action": "unsubscribe", ...}, {"action": "unsubscribe_all"},
  {"action": "subscribe_orders"} and {"action": "unsubscribe_orders"} answer
  with the matching acks.
* {"action": "get_broker_info"}, {"action": "get_supported_brokers"} and
  {"action": "ping", "timestamp": t} answer like the real proxy. Unknown
  actions get {"status": "error", "code": "INVALID_ACTION", ...}.

Every text frame the server receives is appended to the --record file as one
JSON line {"conn": n, "t": time, "frame": "<raw text>"}. Connection events are
recorded as {"conn": n, "event": "open" | "close" | "rejected" | "pong" |
"pong_timeout"}.

Test control messages use {"action": "mock", "cmd": ...}:

* push      {"text": "<raw text>"}      send the text unchanged to this client
* push_many {"texts": ["...", ...]}     send several texts in order
* fragment  {"parts": ["...", ...]}     send one text message as fragments
* order     {"order": {...}}            send an order_update (fields merged)
* close     {"code": 1000, "reason": ""} close this connection gracefully
* abort     {}                          drop the TCP connection without a close frame
* reject    {"count": n}                reject the next n handshakes with HTTP 503
* ping      {}                          ping the client, record "pong" when answered
* silence   {"count": n}                ignore the next n requests of this connection
* shutdown  {}                          stop the server

With --tls-port (0 picks a free port) the same server is also offered over
wss://. A small test PKI is created at start-up in --tls-dir (Python
cryptography package, else the openssl tool):

    ca.pem              test CA; clients trust it through their CA file option
    server.pem/.key     signed by the CA, for localhost and 127.0.0.1
    wrongname.pem/.key  signed by the CA, for wrong-host.invalid only
    other-ca.pem        an unrelated CA that signs nothing used here

The main wss:// listener serves server.pem. A second wss:// listener on a
free port serves wrongname.pem, so a client that trusts ca.pem must still
refuse it because of the host name.

On start-up the ports are written to --ready-file (atomically), one per
line: ws://, wss://, wss:// with the wrong name (0 when TLS is off), and the
process id to --pid-file when given.
"""

import argparse
import asyncio
import json
import os
import shutil
import ssl
import subprocess
import sys
import tempfile
import time
from contextlib import AsyncExitStack
from http import HTTPStatus

from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

BROKER = "mockbroker"
USER_ID = "mockuser"

LTP_SAMPLE = {"ltp": 1234.5, "ltt": 1700000000, "timestamp": 1700000000123}

QUOTE_SAMPLE = {
    "open": 100.5,
    "high": 110.25,
    "low": 95.75,
    "close": 99.5,
    "ltp": 105.25,
    "volume": 123456,
    "last_trade_quantity": 10,
    "avg_trade_price": 104.1,
    "change": 5.75,
    "change_percent": 5.78,
    "timestamp": 1700000000234,
}

DEPTH_SAMPLE = {
    "ltp": 105.25,
    "timestamp": 1700000000345,
    "depth": {
        "buy": [
            {"price": 105.2, "quantity": 100, "orders": 3},
            {"price": 105.15, "quantity": 50, "orders": 2},
            {"price": 105.1, "quantity": 25, "orders": 1},
        ],
        "sell": [
            {"price": 105.3, "quantity": 80, "orders": 4},
            {"price": 105.35, "quantity": 40, "orders": 2},
        ],
    },
}

ORDER_SAMPLE = {
    "type": "order_update",
    "orderid": "SB-0001",
    "symbol": "RELIANCE",
    "exchange": "NSE",
    "action": "BUY",
    "quantity": 10,
    "pricetype": "LIMIT",
    "product": "MIS",
    "order_status": "complete",
    "filled_quantity": 10,
    "pending_quantity": 0,
    "average_price": 2450.5,
    "rejection_reason": "",
    "broker": BROKER,
}

MODE_SAMPLES = {1: LTP_SAMPLE, 2: QUOTE_SAMPLE, 3: DEPTH_SAMPLE}
MODE_LABELS = {1: "LTP", 2: "Quote", 3: "Depth"}
SUPPORTED_BROKERS = ["mockbroker", "otherbroker"]
MAX_DEPTH = 20


def depth_sample(levels):
    """DEPTH_SAMPLE for the default 5 levels, else `levels` generated levels."""
    if levels == 5:
        return DEPTH_SAMPLE
    buy = [{"price": round(105.2 - 0.05 * i, 2), "quantity": 10 * (i + 1), "orders": i + 1}
           for i in range(levels)]
    sell = [{"price": round(105.3 + 0.05 * i, 2), "quantity": 10 * (i + 1), "orders": i + 1}
            for i in range(levels)]
    return {"ltp": 105.25, "timestamp": 1700000000345, "depth": {"buy": buy, "sell": sell}}


class MockState:
    def __init__(self, args):
        self.args = args
        self.conn_counter = 0
        self.reject = 0
        self.stop = None


def record(state, conn, **fields):
    """Append one JSON line to the record file (opened per write)."""
    path = state.args.record
    if not path:
        return
    entry = {"conn": conn, "t": time.time()}
    entry.update(fields)
    line = json.dumps(entry) + "\n"
    for _ in range(20):
        try:
            with open(path, "a", encoding="utf-8") as f:
                f.write(line)
            return
        except OSError:
            # The test may be deleting the file at this moment on Windows.
            time.sleep(0.01)


def market_data(symbol, exchange, mode, depth=5):
    return {
        "type": "market_data",
        "symbol": symbol,
        "exchange": exchange,
        "mode": mode,
        "data": depth_sample(depth) if mode == 3 else MODE_SAMPLES[mode],
    }


def mode_number(mode):
    if isinstance(mode, str):
        for number, label in MODE_LABELS.items():
            if label.lower() == mode.lower():
                return number
        return None
    return mode


async def handle_mock(state, ws, conn, msg, session):
    cmd = msg.get("cmd")
    if cmd == "silence":
        session["silence"] = int(msg.get("count", 1))
    elif cmd == "push":
        await ws.send(msg.get("text", ""))
    elif cmd == "push_many":
        for text in msg.get("texts", []):
            await ws.send(text)
    elif cmd == "fragment":
        await ws.send(list(msg.get("parts", [])))
    elif cmd == "order":
        order = dict(ORDER_SAMPLE)
        order.update(msg.get("order") or {})
        await ws.send(json.dumps(order))
    elif cmd == "close":
        await ws.close(code=int(msg.get("code", 1000)), reason=str(msg.get("reason", "")))
    elif cmd == "abort":
        ws.transport.abort()
    elif cmd == "reject":
        state.reject = int(msg.get("count", 1))
    elif cmd == "ping":
        async def wait_pong():
            try:
                waiter = await ws.ping()
                await asyncio.wait_for(waiter, timeout=5)
                record(state, conn, event="pong")
            except Exception:
                record(state, conn, event="pong_timeout")
        asyncio.get_running_loop().create_task(wait_pong())
    elif cmd == "shutdown":
        if state.stop is not None and not state.stop.done():
            state.stop.set_result(None)


async def handler(state, ws):
    state.conn_counter += 1
    conn = state.conn_counter
    path = getattr(getattr(ws, "request", None), "path", "")
    record(state, conn, event="open", path=path)
    authed = False
    session = {"silence": 0, "subs": []}   # subs: list of (symbol, exchange, mode)
    try:
        async for raw in ws:
            if isinstance(raw, bytes):
                raw = raw.decode("utf-8", "replace")
            record(state, conn, frame=raw)
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await ws.send(json.dumps(
                    {"status": "error", "code": "INVALID_JSON", "message": "Invalid JSON message"}))
                continue
            if not isinstance(msg, dict):
                continue
            action = msg.get("action") or msg.get("type")

            if action == "mock":
                await handle_mock(state, ws, conn, msg, session)
                continue

            if session["silence"] > 0:
                session["silence"] -= 1
                continue

            if action == "get_supported_brokers":
                await ws.send(json.dumps({
                    "type": "supported_brokers", "status": "success",
                    "brokers": SUPPORTED_BROKERS, "count": len(SUPPORTED_BROKERS)}))
                continue

            if action == "ping":
                pong = {"type": "pong", "status": "success",
                        "server_timestamp": int(time.time() * 1000)}
                if msg.get("timestamp") is not None:
                    pong["client_timestamp"] = msg.get("timestamp")
                await ws.send(json.dumps(pong))
                continue

            if action == "authenticate":
                if msg.get("api_key") == state.args.api_key:
                    authed = True
                    await ws.send(json.dumps({
                        "type": "auth",
                        "status": "success",
                        "message": "Authentication successful",
                        "broker": BROKER,
                        "user_id": USER_ID,
                        "supported_features": {"ltp": True, "quote": True, "depth": True},
                    }))
                else:
                    await ws.send(json.dumps(
                        {"type": "auth", "status": "error", "message": "Invalid API key"}))
                continue

            if not authed:
                await ws.send(json.dumps({
                    "status": "error", "code": "NOT_AUTHENTICATED",
                    "message": "You must authenticate first"}))
                continue

            if action == "subscribe":
                symbols = msg.get("symbols")
                if not symbols:
                    symbols = [{"symbol": msg.get("symbol"), "exchange": msg.get("exchange")}]
                mode = mode_number(msg.get("mode", 1))
                depth = int(msg.get("depth", 5) or 5)
                refused = mode == 3 and depth > MAX_DEPTH
                subs = []
                for s in symbols:
                    if refused:
                        subs.append({
                            "symbol": s.get("symbol"), "exchange": s.get("exchange"),
                            "status": "error",
                            "message": f"Depth level {depth} is not supported by this broker",
                            "broker": BROKER})
                    else:
                        subs.append({
                            "symbol": s.get("symbol"), "exchange": s.get("exchange"),
                            "status": "success", "mode": MODE_LABELS.get(mode, mode),
                            "depth": depth, "broker": BROKER})
                        key = (s.get("symbol"), s.get("exchange"), mode)
                        if key not in session["subs"]:
                            session["subs"].append(key)
                await ws.send(json.dumps({
                    "type": "subscribe",
                    "status": "partial" if refused else "success",
                    "subscriptions": subs,
                    "message": "Subscription processing complete",
                    "broker": BROKER,
                }))
                if state.args.auto_push and mode in MODE_SAMPLES and not refused:
                    for s in symbols:
                        await ws.send(json.dumps(
                            market_data(s.get("symbol"), s.get("exchange"), mode, depth)))
            elif action in ("unsubscribe", "unsubscribe_all"):
                if action == "unsubscribe_all":
                    items = [{"symbol": sym, "exchange": exch, "mode": m}
                             for (sym, exch, m) in session["subs"]]
                else:
                    items = [{"symbol": s.get("symbol"), "exchange": s.get("exchange"),
                              "mode": mode_number(s.get("mode", msg.get("mode", 2)))}
                             for s in (msg.get("symbols") or [])]
                successful, failed = [], []
                for it in items:
                    key = (it["symbol"], it["exchange"], it["mode"])
                    entry = {"symbol": it["symbol"], "exchange": it["exchange"],
                             "mode": MODE_LABELS.get(it["mode"], it["mode"]), "broker": BROKER}
                    if key in session["subs"]:
                        session["subs"].remove(key)
                        successful.append(dict(entry, status="success"))
                    else:
                        failed.append(dict(entry, status="error", message="Not subscribed"))
                status = "success" if not failed else ("partial" if successful else "error")
                await ws.send(json.dumps({
                    "type": "unsubscribe",
                    "status": status,
                    "message": "Unsubscription processing complete",
                    "successful": successful,
                    "failed": failed,
                    "broker": BROKER,
                }))
            elif action == "get_broker_info":
                await ws.send(json.dumps({
                    "type": "broker_info", "status": "success", "broker": BROKER,
                    "adapter_status": "connected", "user_id": USER_ID}))
            elif action == "subscribe_orders":
                await ws.send(json.dumps({
                    "type": "subscribe_orders", "status": "success",
                    "message": "Subscribed to order updates"}))
            elif action == "unsubscribe_orders":
                await ws.send(json.dumps({
                    "type": "unsubscribe_orders", "status": "success",
                    "message": "Unsubscribed from order updates"}))
            else:
                await ws.send(json.dumps({
                    "status": "error", "code": "INVALID_ACTION",
                    "message": f"Invalid action: {action}"}))
    except ConnectionClosed:
        pass
    finally:
        record(state, conn, event="close")


def make_process_request(state):
    def process_request(connection, request):
        if state.reject > 0:
            state.reject -= 1
            record(state, 0, event="rejected")
            return connection.respond(HTTPStatus.SERVICE_UNAVAILABLE, "Service unavailable\n")
        return None
    return process_request


SERVER_NAMES = ("localhost", "127.0.0.1")
WRONG_NAMES = ("wrong-host.invalid",)


def make_test_pki(directory):
    """Create the test CA, server certificates and an unrelated CA in directory."""
    os.makedirs(directory, exist_ok=True)
    paths = {name: os.path.join(directory, name) for name in (
        "ca.pem", "ca.key", "server.pem", "server.key",
        "wrongname.pem", "wrongname.key", "other-ca.pem", "other-ca.key")}
    try:
        import cryptography  # noqa: F401
    except ImportError:
        make_test_pki_openssl(directory, paths)
    else:
        make_test_pki_cryptography(paths)
    return paths


def make_test_pki_cryptography(paths):
    import datetime
    import ipaddress
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

    now = datetime.datetime.now(datetime.timezone.utc)

    def write(cert, key, cert_path, key_path):
        with open(key_path, "wb") as f:
            f.write(key.private_bytes(serialization.Encoding.PEM,
                                      serialization.PrivateFormat.TraditionalOpenSSL,
                                      serialization.NoEncryption()))
        with open(cert_path, "wb") as f:
            f.write(cert.public_bytes(serialization.Encoding.PEM))

    def make_ca(common_name):
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)])
        cert = (
            x509.CertificateBuilder()
            .subject_name(name).issuer_name(name)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - datetime.timedelta(days=1))
            .not_valid_after(now + datetime.timedelta(days=7))
            .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
            .add_extension(x509.KeyUsage(
                digital_signature=False, content_commitment=False, key_encipherment=False,
                data_encipherment=False, key_agreement=False, key_cert_sign=True,
                crl_sign=True, encipher_only=False, decipher_only=False), critical=True)
            .add_extension(x509.SubjectKeyIdentifier.from_public_key(key.public_key()), critical=False)
            .sign(key, hashes.SHA256())
        )
        return cert, key

    def make_leaf(ca_cert, ca_key, names):
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        alt = []
        for n in names:
            try:
                alt.append(x509.IPAddress(ipaddress.ip_address(n)))
            except ValueError:
                alt.append(x509.DNSName(n))
        cert = (
            x509.CertificateBuilder()
            .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, names[0])]))
            .issuer_name(ca_cert.subject)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - datetime.timedelta(days=1))
            .not_valid_after(now + datetime.timedelta(days=7))
            .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
            .add_extension(x509.KeyUsage(
                digital_signature=True, content_commitment=False, key_encipherment=True,
                data_encipherment=False, key_agreement=False, key_cert_sign=False,
                crl_sign=False, encipher_only=False, decipher_only=False), critical=True)
            .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
            .add_extension(x509.SubjectAlternativeName(alt), critical=False)
            .add_extension(x509.SubjectKeyIdentifier.from_public_key(key.public_key()), critical=False)
            .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(ca_key.public_key()),
                           critical=False)
            .sign(ca_key, hashes.SHA256())
        )
        return cert, key

    ca_cert, ca_key = make_ca("OpenAlgo MATLAB test CA")
    write(ca_cert, ca_key, paths["ca.pem"], paths["ca.key"])
    write(*make_leaf(ca_cert, ca_key, SERVER_NAMES), paths["server.pem"], paths["server.key"])
    write(*make_leaf(ca_cert, ca_key, WRONG_NAMES), paths["wrongname.pem"], paths["wrongname.key"])
    other_cert, other_key = make_ca("Unrelated test CA")
    write(other_cert, other_key, paths["other-ca.pem"], paths["other-ca.key"])


def make_test_pki_openssl(directory, paths):
    openssl = shutil.which("openssl")
    for candidate in (r"C:\Program Files\Git\usr\bin\openssl.exe", "/usr/bin/openssl"):
        if not openssl and os.path.exists(candidate):
            openssl = candidate
    if not openssl:
        raise RuntimeError("TLS needs the cryptography package or the openssl tool")

    def run(*args):
        subprocess.run([openssl, *args], check=True, capture_output=True)

    def make_ca(stem, common_name):
        ext = os.path.join(directory, stem + ".ext")
        with open(ext, "w", encoding="ascii") as f:
            f.write("basicConstraints=critical,CA:TRUE,pathlen:0\n"
                    "keyUsage=critical,keyCertSign,cRLSign\n"
                    "subjectKeyIdentifier=hash\n")
        run("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "7",
            "-keyout", paths[stem + ".key"], "-out", paths[stem + ".pem"],
            "-subj", "/CN=" + common_name, "-extensions", "v3_ca_test",
            "-config", openssl_config(directory, ext))

    def make_leaf(stem, names):
        alt = ",".join(("IP:" if n.replace(".", "").isdigit() else "DNS:") + n for n in names)
        ext = os.path.join(directory, stem + ".ext")
        with open(ext, "w", encoding="ascii") as f:
            f.write("basicConstraints=critical,CA:FALSE\n"
                    "keyUsage=critical,digitalSignature,keyEncipherment\n"
                    "extendedKeyUsage=serverAuth\n"
                    "subjectKeyIdentifier=hash\n"
                    "authorityKeyIdentifier=keyid\n"
                    f"subjectAltName={alt}\n")
        csr = os.path.join(directory, stem + ".csr")
        run("req", "-new", "-newkey", "rsa:2048", "-nodes",
            "-keyout", paths[stem + ".key"], "-out", csr, "-subj", "/CN=" + names[0])
        run("x509", "-req", "-in", csr, "-CA", paths["ca.pem"], "-CAkey", paths["ca.key"],
            "-CAcreateserial", "-days", "7", "-sha256", "-extfile", ext,
            "-out", paths[stem + ".pem"])

    make_ca("ca", "OpenAlgo MATLAB test CA")
    make_leaf("server", SERVER_NAMES)
    make_leaf("wrongname", WRONG_NAMES)
    make_ca("other-ca", "Unrelated test CA")


def openssl_config(directory, ext_file):
    """A minimal openssl req config whose v3_ca_test section holds ext_file."""
    path = ext_file + ".cnf"
    with open(ext_file, encoding="ascii") as f:
        ext = f.read()
    with open(path, "w", encoding="ascii") as f:
        f.write("[req]\ndistinguished_name=dn\n[dn]\n[v3_ca_test]\n" + ext)
    return path


async def main(args):
    state = MockState(args)
    state.stop = asyncio.get_running_loop().create_future()

    async def conn_handler(ws):
        await handler(state, ws)

    async with AsyncExitStack() as stack:
        server = await stack.enter_async_context(serve(
            conn_handler, args.host, args.port,
            process_request=make_process_request(state), compression=None))
        port = list(server.sockets)[0].getsockname()[1]
        tls_port = 0
        wrong_port = 0
        if args.tls_port >= 0:
            pki = make_test_pki(args.tls_dir or tempfile.mkdtemp(prefix="mockws"))
            listeners = []
            for stem, wanted in (("server", args.tls_port), ("wrongname", 0)):
                ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                ctx.load_cert_chain(pki[stem + ".pem"], pki[stem + ".key"])
                tls_server = await stack.enter_async_context(serve(
                    conn_handler, args.host, wanted, ssl=ctx,
                    process_request=make_process_request(state), compression=None))
                listeners.append(list(tls_server.sockets)[0].getsockname()[1])
            tls_port, wrong_port = listeners
            print(f"mock server listening on wss://{args.host}:{tls_port} "
                  f"(wrong name on {wrong_port})", flush=True)
        if args.pid_file:
            with open(args.pid_file, "w", encoding="utf-8") as f:
                f.write(str(os.getpid()))
        if args.ready_file:
            tmp = args.ready_file + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(f"{port}\n{tls_port}\n{wrong_port}\n")
            os.replace(tmp, args.ready_file)
        print(f"mock server listening on {args.host}:{port}", flush=True)
        try:
            await asyncio.wait_for(state.stop, timeout=args.lifetime)
        except asyncio.TimeoutError:
            print("mock server lifetime reached", flush=True)


def parse_args(argv):
    p = argparse.ArgumentParser(description="Mock OpenAlgo WebSocket proxy")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=0, help="0 picks a free port")
    p.add_argument("--ready-file", default="", help="file that receives the bound port")
    p.add_argument("--pid-file", default="", help="file that receives the process id")
    p.add_argument("--tls-port", type=int, default=-1,
                   help="also serve wss:// on this port (0 picks a free port, -1 disables)")
    p.add_argument("--tls-dir", default="", help="directory for the test CA and certificates")
    p.add_argument("--record", default="", help="JSON lines file for received frames")
    p.add_argument("--api-key", default="test-api-key", help="the key that authenticates")
    p.add_argument("--no-auto-push", dest="auto_push", action="store_false",
                   help="do not push sample market data after a subscribe")
    p.add_argument("--lifetime", type=float, default=900.0,
                   help="seconds after which the server exits on its own")
    return p.parse_args(argv)


if __name__ == "__main__":
    asyncio.run(main(parse_args(sys.argv[1:])))

# Changelog

All notable changes to the OpenAlgo MATLAB library are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `tls_ca_file` on the feed client: a PEM file of CA certificates trusted in
  addition to the system trust store, for a `wss://` server with a private
  CA. Supported by the .NET, Python and Java TLS providers; the host name is
  still verified.

### Fixed

- The Java TLS provider now verifies the server's host name (HTTPS endpoint
  identification). Before, it checked only the certificate chain.
- The `wss://` feed tests on Java failed on CI because Java cannot turn
  certificate verification off. The tests now trust a test CA through
  `tls_ca_file` with every provider and also check that a wrong host name
  and an unrelated CA are rejected.

## [1.0.0] - 2026-10-16

First release. The library is a MATLAB replica of the OpenAlgo Python SDK
2.0.5 (the `openalgo` package on PyPI), without the technical indicators
(`ta`). If you already use the Python SDK, the method names, parameter names,
defaults, request payloads and error results are the same, so its
documentation and examples carry over almost line for line:

```matlab
client = openalgo.api(api_key=getenv("OPENALGO_API_KEY"), host="http://127.0.0.1:5000");
resp = client.placeorder(strategy="Python", symbol="SBIN", action="BUY", ...
    exchange="NSE", price_type="MARKET", product="MIS", quantity=1);
```

It needs only base MATLAB (no toolboxes, no Python, no JVM for plain `ws://`
feeds). It is tested on R2026b; it is written for R2022b or later, but earlier
releases have not been tested.

### Mirrors the Python SDK 2.0.5

- **Orders**: `placeorder`, `placesmartorder`, `basketorder`, `splitorder`,
  `orderstatus`, `openposition`, `modifyorder`, `cancelorder`,
  `closeposition`, `cancelallorder`.
- **GTT orders**: `placegttorder`, `modifygttorder`, `cancelgttorder`,
  `gttorderbook`, with the same client-side SINGLE/OCO validation and the
  same numeric payload (`700.0`, `null` legs for SINGLE).
- **Market data**: `quotes`, `multiquotes`, `depth`, `symbol`, `search`,
  `history` (returns a timetable), `intervals`, `interval`, `expiry`,
  `instruments` (returns a table; all exchanges when none is given),
  `syntheticfuture`.
- **Account**: `funds`, `orderbook`, `tradebook`, `positionbook`, `holdings`,
  `analyzerstatus`, `analyzertoggle`, `margin`.
- **Options**: `optiongreeks`, `optionsorder`, `optionsymbol`,
  `optionsmultiorder`, `optionchain`, including the deprecation warnings for
  `strike_int` and the `strategy` argument of `optionsymbol`
  (warning identifier `openalgo:deprecated`).
- **Strategy module** (API key surface): `strategylist`, `strategystatus`,
  `strategystart`, `strategystop`, `strategycloseall`, `strategycloseleg`,
  `strategyruns`, `strategyorders`, `strategyevents`. Non-200 answers with a
  JSON body (for example a 409 with `stop_pending`) are returned as is, with
  `code` attached, as in the Python SDK.
- **Strategy webhook**: `openalgo.Strategy` with `start`, `stop`, `signal`,
  `long_entry`, `long_exit`, `short_entry`, `short_exit`, `send` and
  `close`. The token never appears when the object is displayed.
- **Notifications and calendar**: `telegram`, `whatsapp`, `holidays`,
  `timings`, and `close` on the client.
- **WebSocket feed**: `connect`, `disconnect`, `subscribe_ltp`,
  `subscribe_quote`, `subscribe_depth`, `subscribe_orders`, the matching
  `unsubscribe_*` methods, `get_ltp`, `get_quotes`, `get_depth`, `get_orders`,
  callbacks, and automatic reconnection with subscription replay
  (`auto_reconnect`, on by default). `ws://` uses `tcpclient`; `wss://` uses
  .NET on Windows, the MATLAB Python interface (Python 3.9 to 3.13) or the
  JVM, whichever is available, with certificate verification on.
- **Errors**: REST methods never raise for server or network problems. They
  return a struct with `status` `'error'`, `message` and `error_type`
  (`http_error`, `json_error`, `api_error`, `timeout_error`,
  `connection_error`, `unknown_error`, `validation_error`, `no_data`,
  `processing_error`), plus `code` and `raw_response` where the Python SDK
  includes them. Wrong arguments raise errors with identifiers such as
  `openalgo:missingArgument` and `openalgo:unexpectedArgument`, where Python
  raises `TypeError`.

### Added (not in the Python SDK)

Methods for the documented OpenAlgo server endpoints that the Python SDK does
not wrap. They follow the same calling convention and error handling.

- `ping` (authenticated connectivity check) and `pnlsymbols` (sandbox P&L by
  symbol).
- `multioptiongreeks`: Greeks for 1 to 50 options in one request, with the
  count checked before sending.
- `ticker`: the ticker-compatible history endpoint, as JSON (struct) or as
  comma-separated text.
- `chart` and `updatechart`: read and update the stored chart preferences.
- Telegram bot management: `telegramconfig`, `updatetelegramconfig`,
  `telegramstart`, `telegramstop`, `telegramusers`, `telegrambroadcast`,
  `telegramstats`, `telegrampreferences`, `updatetelegrampreferences`.
- Feed: `wait` (keep processing the feed in scripts), `unsubscribe_all`,
  `get_broker_info`, `get_supported_brokers`, `ws_ping` (round trip in
  milliseconds) and a `depth` argument on `subscribe_depth` (5, 20, 30 or 50
  levels).

### MATLAB specific behaviour to know before adopting

- **Calling convention.** Parameters are name=value with the exact,
  case-sensitive Python names. Parameters that are positional in Python
  (`analyzertoggle(mode)`, `holidays(year)`, `timings(date)`,
  `whatsapp(message)`, `Strategy.start(mode)`, `Strategy.signal(action)`)
  also accept a leading positional value. `[]` stands for Python `None`.
  Lists are cell arrays or struct arrays and always go out as JSON arrays,
  even with one element.
- **Numbers.** A whole-valued double is treated as a Python `int`, so
  `price=50` and `price=50.0` both send `"50"` where Python's `str(50.0)`
  sends `"50.0"`. Pass text (`price="50.0"`) when the exact text matters.
  Large values are never written in exponent form (`100000`, not `1e+05`).
- **Responses** are decoded with `jsondecode`: JSON `null` becomes `[]`, a
  one-element array of objects becomes a 1x1 struct, arrays of objects with
  the same keys become struct arrays, numeric arrays become column vectors,
  and keys that are not valid MATLAB names are renamed.
- **history** returns a timetable whose row times are in the Asia/Kolkata
  time zone for intraday intervals (MATLAB reports the zone under its
  canonical alias `Asia/Calcutta`) and zone-less for `D`, `W` and `M`, like
  the pandas index of the Python SDK. **instruments** returns a table.
- **Feed callbacks** run on a MATLAB timer, so they fire while MATLAB is idle,
  during `pause` and during `client.wait`; there are no background threads.

### Quality

- 118 REST tests run every method against a local mock server and compare
  the request body byte for byte with what the Python SDK 2.0.5 sends,
  including the error paths (timeouts, refused connections, non-JSON and
  non-object bodies, closed clients).
- 79 WebSocket feed tests run against a mock feed server over `ws://` and
  over each `wss://` transport.
- 12 live tests exercise every read-only method, the sandbox order, GTT and
  options flows, the additions and the live feed against a real OpenAlgo
  server in analyzer mode; they run only when `OPENALGO_API_KEY` is set.
- A cross-language parity harness (`tools/parity`) replays 200 scenarios
  through the Python SDK and this library and diffs the requests and
  results.

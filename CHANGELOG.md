# Changelog

All notable changes to the OpenAlgo MATLAB library are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-10-16

Upgrade if you connect to a hosted `wss://` server, especially when the
Java TLS provider is used (it is picked when neither .NET nor the MATLAB
Python interface is available, or when `tls_transport` is `"java"`). Check
the behaviour change below if you place orders without a `strategy` name.

### Security

- The Java TLS provider now verifies the server's host name (HTTPS endpoint
  identification). In 1.0.0 it checked only the certificate chain, so a
  valid certificate issued for a different host was accepted. The .NET and
  MATLAB Python interface providers already verified the host name; all
  three providers now do.

### Added

- `tls_ca_file` on the feed client: a PEM file of CA certificates trusted in
  addition to the system trust store, for a `wss://` server whose
  certificate comes from a private CA. Set it before `connect()`:
  `client.tls_ca_file = "C:\certs\my-private-ca.pem";`. Supported by the
  .NET, MATLAB Python interface and Java TLS providers; the host name is
  still verified.

### Changed

- **Behaviour change: the default strategy name is now `"MATLAB"`.** Orders
  and requests sent without a `strategy` argument (`placeorder`,
  `placesmartorder`, `basketorder`, `splitorder`, `orderstatus`,
  `openposition`, `modifyorder`, `cancelorder`, `closeposition`,
  `cancelallorder`, `optionsorder`, `placegttorder`, `modifygttorder`,
  `cancelgttorder`) are now tagged `MATLAB` instead of `Python`. If you
  filter the order book, close positions or cancel orders by the default
  strategy name, update those filters, or pass `strategy=` explicitly.
  Calls that pass a strategy name are not affected.

### Fixed

- Help text: every method that has a strategy default now states
  `Default "MATLAB".`; the calling convention in `help openalgo` and
  `help openalgo.api` is described on its own terms; the utility and
  management methods are listed under their own heading; and
  `help openalgo.FeedAPI` explains that an `https://` host derives the
  `wss://<host>/ws` feed URL by itself.
- The `wss://` feed tests on Java failed on CI because Java cannot turn
  certificate verification off. The tests now trust a test CA through
  `tls_ca_file` with every provider and also check that a wrong host name
  and an unrelated CA are rejected.

## [1.0.0] - 2026-10-16

First release. The OpenAlgo MATLAB library gives MATLAB the full OpenAlgo
REST API, the strategy webhook and the live WebSocket feed:

```matlab
client = openalgo.api(api_key=getenv("OPENALGO_API_KEY"), host="http://127.0.0.1:5000");
resp = client.placeorder(strategy="MATLAB Strategy", symbol="SBIN", action="BUY", ...
    exchange="NSE", price_type="MARKET", product="MIS", quantity=1);
```

It needs only base MATLAB: no toolboxes, and nothing else for a local
`ws://` feed. It is tested on MATLAB R2026b.

### Added

- **Orders**: `placeorder`, `placesmartorder`, `basketorder`, `splitorder`,
  `orderstatus`, `openposition`, `modifyorder`, `cancelorder`,
  `closeposition`, `cancelallorder`.
- **GTT orders**: `placegttorder`, `modifygttorder`, `cancelgttorder`,
  `gttorderbook`. Impossible SINGLE/OCO trigger specs are refused before
  anything is sent, as a `validation_error` struct.
- **Market data**: `quotes`, `multiquotes`, `depth`, `symbol`, `search`,
  `history` (returns a timetable), `ticker` (candles as JSON or as
  comma-separated text rows), `intervals`, `interval`, `expiry`,
  `instruments` (returns a table; all exchanges when none is given),
  `syntheticfuture`.
- **Account**: `funds`, `orderbook`, `tradebook`, `positionbook`, `holdings`,
  `margin`, `pnlsymbols` (sandbox P&L by symbol), `analyzerstatus`,
  `analyzertoggle`.
- **Options**: `optiongreeks`, `multioptiongreeks` (Greeks for 1 to 50
  options in one request, with the count checked before sending),
  `optionsorder`, `optionsymbol`, `optionsmultiorder`, `optionchain`. The
  deprecated `strike_int` and the `strategy` argument of `optionsymbol` still
  work and warn with the identifier `openalgo:deprecated`.
- **Strategy module** (API key surface): `strategylist`, `strategystatus`,
  `strategystart`, `strategystop`, `strategycloseall`, `strategycloseleg`,
  `strategyruns`, `strategyorders`, `strategyevents`. Non-200 answers with a
  JSON body (for example a 409 with `stop_pending`) are returned as is, with
  the HTTP status attached as `code`.
- **Strategy webhook**: `openalgo.Strategy` with `start`, `stop`, `signal`,
  `long_entry`, `long_exit`, `short_entry`, `short_exit`, `send` and
  `close`. Every documented outcome is returned with its `result` label.
- **Notifications**: `telegram` and `whatsapp` alerts, and Telegram bot
  management: `telegramconfig`, `updatetelegramconfig`, `telegramstart`,
  `telegramstop`, `telegramusers`, `telegrambroadcast`, `telegramstats`,
  `telegrampreferences`, `updatetelegrampreferences`.
- **Utilities**: `ping` (checks the API key and the broker session),
  `holidays`, `timings`, `chart` and `updatechart` (stored chart
  preferences), and `close` on the client.
- **WebSocket feed**: `connect`, `disconnect`, `subscribe_ltp`,
  `subscribe_quote`, `subscribe_depth`, `subscribe_orders`, the matching
  `unsubscribe_*` methods, `unsubscribe_all`, `get_ltp`, `get_quotes`,
  `get_depth`, `get_orders`, callbacks, and automatic reconnection with
  subscription replay (`auto_reconnect`, on by default).
  `subscribe_depth` requests 5, 20, 30 or 50 levels where the broker supports
  them. `get_broker_info`, `get_supported_brokers` and `ws_ping` (round trip
  in milliseconds) query the feed server, and `wait` keeps the feed running
  in scripts. `verbose` levels 0, 1 and 2 control the feed log.
- **Hosted servers**: an `https://` host gives the feed URL
  `wss://<host>/ws` automatically. `wss://` runs over .NET on Windows,
  MATLAB's Python interface (Python 3.9 to 3.13) or Java, whichever is
  available, with certificate verification on.
- **Errors**: REST methods never raise for server or network problems. They
  return a struct with `status` `'error'`, `message` and `error_type`
  (`http_error`, `json_error`, `api_error`, `timeout_error`,
  `connection_error`, `unknown_error`, `validation_error`, `no_data`,
  `processing_error`), plus `code` and `raw_response` where they apply.
  Wrong arguments raise MATLAB errors with identifiers such as
  `openalgo:missingArgument` and `openalgo:unexpectedArgument`.
- **Help text** for every class and method, for example
  `help openalgo.api/placeorder` and `help openalgo.FeedAPI`.

### How it works in MATLAB

- **Arguments** are name=value pairs with exact, case-sensitive names. A few
  methods also take their main value without a name (`analyzertoggle(true)`,
  `holidays(2026)`, `timings(date)`, `whatsapp(message)`,
  `Strategy.start(mode)`, `Strategy.signal(action)`). `[]` means "not set"
  and is not sent. Lists are cell arrays or struct arrays and always go out
  as JSON arrays, even with one element.
- **Numbers** can be passed as numbers. A whole number is sent without a
  decimal point, so `price=50` and `price=50.0` both send `"50"`; pass text
  (`price="50.0"`) when the exact text matters. Large values are never
  written in exponent form (`100000`, not `1e+05`).
- **Responses** are structs decoded with `jsondecode`: JSON `null` becomes
  `[]`, a one-element array of objects becomes a 1x1 struct, arrays of
  objects with the same keys become struct arrays, numeric arrays become
  column vectors, and keys that are not valid MATLAB names are renamed.
- **history** returns a timetable whose row times are in the Asia/Kolkata
  time zone for intraday intervals (MATLAB reports the zone under its
  canonical alias `Asia/Calcutta`) and zone-less for `D`, `W` and `M`.
  **instruments** returns a table.
- **Feed callbacks** run on a MATLAB timer, so they fire while MATLAB is idle,
  during `pause` and during `client.wait`; use `client.wait(seconds)` in
  `matlab -batch` scripts.
- **Credentials stay hidden**: displaying the client never shows the API
  key, and displaying an `openalgo.Strategy` never shows the webhook token.

### Quality

- 118 REST tests run every method against a local mock server and check the
  request body byte for byte, including the error paths (timeouts, refused
  connections, non-JSON and non-object bodies, closed clients).
- 79 WebSocket feed tests run against a mock feed server over `ws://` and
  over each `wss://` transport.
- 12 live tests exercise every read-only method, the sandbox order, GTT and
  options flows and the live feed against a real OpenAlgo server in analyzer
  mode; they run only when `OPENALGO_API_KEY` is set.

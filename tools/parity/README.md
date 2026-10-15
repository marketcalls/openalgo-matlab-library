# OpenAlgo client parity harness

This harness checks that the R and MATLAB OpenAlgo clients send exactly the
same HTTP requests as the OpenAlgo Python SDK, and return the same results. It
covers the REST surface and the strategy webhook sender. Indicators and the
WebSocket feed are out of scope.

The Python SDK is the reference. Every runner executes the same scenarios
against a local recording mock server. `compare.py` then diffs the R and
MATLAB outputs against the Python output.

The same files live in both repositories, under `tools/parity/` in each. The
R repository also holds `run_r.R`. The folder is excluded from the R package
build by `.Rbuildignore` (`^tools$`).

## Requirements

- Python 3.9 or later, with `httpx` and `pandas` (needed by the SDK itself).
  `mock_server.py` and `compare.py` use only the standard library.
- The Python SDK source. The default location is
  `../../../openalgo-python-library`, a checkout next to this repository.
  Set `OPENALGO_PYTHON_LIB` or pass `--lib` to use another location. The
  runner stubs `openalgo.indicators`, so the compiled indicator extension is
  not needed.
- R 4.1 or later, with R6, curl, jsonlite, websocket and later.
- MATLAB (tested on R2026b), with `python` on PATH. Python is used to start the
  mock server and to run `prepare_matlab.py`.

## Running

Run every command from this folder. Each runner starts its own mock server on
a free port and stops it when it finishes.

```sh
# 1. Python reference -> out/python.json
python run_python.py

# 2a. R (sources R/*.R from this working tree in DESCRIPTION Collate order) -> out/r.json
Rscript run_r.R
#     or test the installed package instead:
Rscript run_r.R --installed

# 2b. MATLAB -> out/matlab.json
matlab -batch "run_matlab"

# 3. Compare (exit code 0 = parity, 1 = failures, 2 = nothing to compare)
python compare.py
```

Useful options:

| Command | Option | Effect |
| --- | --- | --- |
| all runners | `--only TEXT` (MATLAB: `only="TEXT"`) | Run only the scenarios whose id contains TEXT. |
| all runners | `--mock-url URL` (MATLAB: `mock_url="URL"`) | Use a mock server that is already running, for example one started with `python mock_server.py --port 8799`. |
| `run_r.R` | `--python PATH` | The Python interpreter that starts the mock server. |
| `run_matlab` | `python="PATH"` | The Python interpreter that starts the mock server. |
| `run_matlab` | `lib="PATH"` | Root of the MATLAB library. The default is two folders up; the runner adds the parent of the `+openalgo` folder to the path. |
| `compare.py` | `--lang r` or `--lang matlab` | Compare one language only. |
| `compare.py` | `--require r` | Fail if `out/r.json` is missing. By default a missing output is skipped. |
| `compare.py` | `--only TEXT` | Compare only the scenarios whose id contains TEXT. |
| `compare.py` | `-v` | Also list the scenarios that pass. |

A full run takes about 75 s in Python and about 20 s in R. Most of the time
goes to the timeout scenarios and the refused-connection scenarios.
`compare.py` also writes `out/compare_<lang>.json` for tools.

## Files

| File | Purpose |
| --- | --- |
| `mock_server.py` | Threaded `http.server` mock. It records every request (method, raw path, query, headers, raw and parsed body) under the current scenario, appends each one to `out/requests_<lang>.jsonl`, and answers from the scenario's response rules. |
| `scenarios.json` | 200 scenarios. Each names the method, its arguments, client options and the mock responses. |
| `run_python.py`, `run_r.R`, `run_matlab.m` | The runners. Each writes `out/<lang>.json`. |
| `prepare_matlab.py` | Writes `scenarios.matlab.json`, the type-tagged form that MATLAB reads. `run_matlab` runs it automatically when it is out of date. |
| `matlab_calling.json` | Optional list of the parameters that the MATLAB library takes positionally rather than as name=value pairs. |
| `compare.py` | The diff and the PASS/FAIL report. |
| `allowlist.json` | Known, justified differences, each with its reason. |
| `parity_common.py` | Mock server lifecycle helpers for the Python scripts. |

## Mock server

The control endpoints are:

- `GET /__control__/ping`
- `POST /__control__/scenario` with the body `{"id", "rules"}`
- `GET /__control__/requests?id=...[&bare=1]`
- `POST /__control__/shutdown`

A rule can match on method, path (wildcards allowed) and query parameters, and
can be limited to a number of uses with `times`. A rule answers with one of
these:

- `status` plus a `json` body
- `status` plus a raw `body`, for non-JSON or empty bodies
- `delay`, which sleeps longer than the client timeout
- `action: "close"`, which drops the connection without a response

Every response sends `Connection: close`. Without it, a client could retry a
request on a stale pooled connection, and the request counts would differ
between languages.

For the refused-connection scenarios, the server keeps a second socket bound
but not listening, and the `$CLOSED` placeholder points at it. Connections to
it are refused.

## Scenarios

The scenario ids are grouped by area:

| Group | What it covers |
| --- | --- |
| `orders.*` | Every order method: defaults only, all optional arguments, and extra kwargs that Python `str()`-converts. For example 100000 becomes "100000" (not "1e+05"), 750.5 becomes "750.5", True becomes "True", 0.30000000000000004 keeps its shortest round-trip form, and a null kwarg is dropped. Also a one-element basket, a numeric order id, Unicode text, and a missing required argument. |
| `gtt.*` | GTT place, modify, cancel and order book. Numeric JSON fields, null stoploss and target for SINGLE, and case folding of trigger_type and action. Every SINGLE and OCO validation rule (these send no request). |
| `strategyapi.*` | Every strategy module method. int() conversion of ids, filters, `mode` required, and 404 or 409 bodies passed through with `code`. |
| `data.*` | Every data method. History conversion: unsorted rows, a duplicate timestamp with different values (the first wins), intraday rows converted to Asia/Kolkata, and daily rows left naive. History empty, error and processing-error paths. Instruments for one exchange (GET with a query string) and for all exchanges, where some exchanges fail with 500, an api error, empty data, a non-JSON body, a timeout or an array body, and one exchange adds an extra column. |
| `account.*` | Account methods. The margin rules (stringified fields, '0' defaults, pass-through fields) and its validations: empty, 51 positions, exactly 50, not a list. |
| `options.*` | Options methods. Deprecation warnings, leg type coercion, unknown leg keys dropped, and a missing strategy. |
| `notify.*` | Telegram, and every WhatsApp addressing mode. |
| `utilities.*` | Market holidays and timings. The default `timings` date is compared by format only. |
| `errors.A.*` | Error paths of the response handler shared by orders, data, account, options, notifications and utilities. Python's method resolution order makes the order module's handler serve all of them, so the WhatsApp and utilities error scenarios check that the R and MATLAB clients do not use those modules' own handlers. |
| `errors.B.*` | Error paths of `_post`, used by the GTT and strategy modules. |
| `client.*` | API version, and a host with a trailing slash. Python keeps the slash, so the path becomes `//api/v1/...`. |
| `webhook.*` | The `Strategy` webhook sender: every method, legacy `webhook_id`, token precedence, trailing slash, `webhook_url`, a missing or empty token, the removed `strategyorder`, and every error path. |

Each error family is covered by these cases:

- 200 with `{"status":"error"}`
- a non-200 JSON body
- a non-200 text body
- an empty body
- a 200 non-JSON body
- a JSON array or string body
- a timeout (client timeout 1 s against a 3 s delay)
- connection refused
- a dropped connection

## Argument encoding

Scenario arguments are language-neutral JSON, and each runner maps them to an
idiomatic call that uses named arguments only:

| JSON | Python | R | MATLAB |
| --- | --- | --- | --- |
| string | `str` | character(1) | string scalar |
| number | int/float as written | double | double |
| true/false | bool | TRUE/FALSE | true/false |
| null | None | NULL | `[]` |
| object | dict | named list | struct |
| array of scalars | list | atomic vector `c(...)` | string array, or numeric or logical row |
| array of objects | list of dicts | list of named lists | cell array of structs |
| `{"$list": [...]}` | list | unnamed `list(...)` | cell array |

Write whole numbers without a decimal point. R and MATLAB users write
`quantity = 100` and have no integer and float distinction, so a scenario
with `100.0` would test the encoding instead of the client.

The `$MOCK` and `$CLOSED` placeholders in the client options and in the
`Strategy` constructor arguments are replaced with the mock server's URL and
with a refused port. In MATLAB, `host_url` and `webhook_id` are passed to the
`Strategy` constructor positionally. Everything else is passed as name=value
pairs, unless `matlab_calling.json` says otherwise.

## Normalized results

Each runner records, for every scenario:

- the requests the mock server saw
- the outcome: either `{"raised": false, "value": ...}`, or
  `{"raised": true, "error_class", "message"}`
- the warnings issued

Dicts, named lists and structs become JSON objects. Data frames and
timetables become `{"__type__": "table", "columns", "nrow", "tz", "records"}`.
In that form, timestamps are ISO 8601 strings, with a `+05:30` style offset
when they carry a time zone. `tz` maps each date-time column to its zone, or
to null when the column is naive. The index of a pandas frame and the row
times of a MATLAB timetable become ordinary columns, so all three languages
compare the same way.

## Comparison rules

### Requests

Requests are compared on these fields:

- the count
- method and raw path
- query parameters
- the Content-Type media type (parameters such as `charset` are ignored)
- the body

JSON bodies are compared semantically and type-sensitively:

- a string never equals a number
- a boolean never equals a number
- null only equals null
- 1 equals 1.0

### Results

These parts of the result are compared:

- whether the call raised
- the message, when both sides raised
- the normalized return value
- the number of warnings

The text of the warnings is not compared.

### Allowlist

A difference can be allowed only by a rule in `allowlist.json`. Each rule
gives the scenario and diff-path patterns it covers, the languages, a
predicate that the actual value must satisfy, and a reason. Allowed
differences are printed as ALLOWED, with the rule id. Rules that no run used
are listed at the end of the report.

## Adding a scenario

1. Add an entry to `scenarios.json`.
2. Rerun `python run_python.py` to refresh the reference.
3. Rerun the other runners.
4. Run `python compare.py`.

If the difference is a genuine host-language difference rather than a bug,
add an allowlist rule with a reason.

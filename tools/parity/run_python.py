#!/usr/bin/env python3
"""Run every parity scenario against the Python SDK (the reference) and write out/python.json.

Usage:
    python run_python.py [--lib PATH] [--only SUBSTRING] [--mock-url URL]

--lib defaults to $OPENALGO_PYTHON_LIB, else ../../../openalgo-python-library
(the SDK checked out next to this repository).
"""

import argparse
import datetime
import json
import math
import os
import platform
import sys
import time
import types
import warnings

from parity_common import OUT_DIR, MockServer, clean_request, load_scenarios, substitute

HERE = os.path.dirname(os.path.abspath(__file__))


def import_sdk(lib):
    # The indicators subpackage needs a compiled extension that the REST
    # surface does not use; a stub keeps `import openalgo` working without it.
    stub = types.ModuleType("openalgo.indicators")
    stub.ta = None
    sys.modules["openalgo.indicators"] = stub
    sys.path.insert(0, lib)
    import openalgo  # noqa: E402
    return openalgo


def decode_arg(value):
    """Language-neutral argument -> Python value."""
    if isinstance(value, dict):
        if set(value) == {"$list"}:
            return [decode_arg(v) for v in value["$list"]]
        return {k: decode_arg(v) for k, v in value.items()}
    if isinstance(value, list):
        return [decode_arg(v) for v in value]
    return value


def normalize(value):
    """Return value -> JSON-ready form shared by all runners."""
    import numpy as np
    import pandas as pd

    if isinstance(value, pd.DataFrame):
        return normalize_frame(value)
    if isinstance(value, dict):
        return {str(k): normalize(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [normalize(v) for v in value]
    if isinstance(value, (bool, np.bool_)):
        return bool(value)
    if isinstance(value, (int, np.integer)):
        return int(value)
    if isinstance(value, (float, np.floating)):
        v = float(value)
        return None if math.isnan(v) or math.isinf(v) else v
    if isinstance(value, pd.Timestamp):
        return None if pd.isna(value) else value.isoformat()
    if isinstance(value, (datetime.datetime, datetime.date)):
        return value.isoformat()
    if value is None or isinstance(value, str):
        return value
    if value is pd.NaT or (not isinstance(value, (list, dict)) and pd.isna(value)):
        return None
    return repr(value)


def normalize_frame(df):
    import pandas as pd

    frame = df
    if not isinstance(df.index, pd.RangeIndex) or df.index.name is not None:
        frame = df.reset_index()
    tz = {}
    for col in frame.columns:
        if pd.api.types.is_datetime64_any_dtype(frame[col]):
            col_tz = getattr(frame[col].dt, "tz", None)
            tz[str(col)] = None if col_tz is None else str(col_tz)
    records = []
    for row in frame.itertuples(index=False, name=None):
        records.append({str(c): normalize(v) for c, v in zip(frame.columns, row)})
    return {"__type__": "table", "columns": [str(c) for c in frame.columns],
            "nrow": int(len(frame)), "tz": tz, "records": records}


def run_scenario(openalgo, mock, sc, api_key):
    mock.start_scenario(sc)
    sub = lambda v: substitute(v, mock.base, mock.closed_base)  # noqa: E731
    args = {k: decode_arg(v) for k, v in sc.get("args", {}).items()}
    outcome = None
    caught = []
    obj = None
    with warnings.catch_warnings(record=True) as wlist:
        warnings.simplefilter("always")
        try:
            if sc.get("target", "api") == "strategy":
                obj = openalgo.Strategy(**sub(sc.get("strategy") or {}))
            else:
                copts = dict(sc.get("client") or {})
                copts.setdefault("host", "$MOCK")
                obj = openalgo.api(api_key=api_key, **sub(copts))
            attr = getattr(obj, sc["method"])
            value = attr if sc.get("property") else attr(**args)
            outcome = {"raised": False, "value": normalize(value)}
        except Exception as exc:  # the scenario records the raise
            outcome = {"raised": True, "error_class": type(exc).__name__, "message": str(exc)}
        finally:
            if obj is not None and hasattr(obj, "close"):
                obj.close()
        caught = [str(w.message) for w in wlist]
    reqs = [clean_request(r) for r in mock.requests_for(sc["id"])]
    return {"requests": reqs, "outcome": outcome, "warnings": caught}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lib", default=os.environ.get("OPENALGO_PYTHON_LIB") or
                    os.path.normpath(os.path.join(HERE, "..", "..", "..", "openalgo-python-library")))
    ap.add_argument("--only", help="run only scenarios whose id contains this text")
    ap.add_argument("--mock-url", help="use an already running mock server")
    ap.add_argument("--out", default=os.path.join(OUT_DIR, "python.json"))
    args = ap.parse_args()

    openalgo = import_sdk(args.lib)
    doc = load_scenarios()
    mock = MockServer("python", args.mock_url)
    results = {}
    t0 = time.time()
    try:
        for sc in doc["scenarios"]:
            if args.only and args.only not in sc["id"]:
                continue
            t = time.time()
            results[sc["id"]] = run_scenario(openalgo, mock, sc, doc["api_key"])
            results[sc["id"]]["seconds"] = round(time.time() - t, 3)
            o = results[sc["id"]]["outcome"]
            print("%-55s %s" % (sc["id"], "raised" if o["raised"] else "ok"))
    finally:
        mock.stop()
    out = {
        "lang": "python",
        "meta": {"mock_base": mock.base, "closed_base": mock.closed_base,
                 "sdk_version": getattr(openalgo, "__version__", None),
                 "runtime": "Python " + platform.python_version(),
                 "generated": datetime.datetime.now().isoformat(timespec="seconds"),
                 "seconds": round(time.time() - t0, 1)},
        "results": results,
    }
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=1, ensure_ascii=False, allow_nan=False)
    print("wrote %s (%d scenarios, %.1fs)" % (args.out, len(results), time.time() - t0))


if __name__ == "__main__":
    main()

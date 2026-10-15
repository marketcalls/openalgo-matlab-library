#!/usr/bin/env python3
"""Write scenarios.matlab.json: scenarios.json in a type-tagged form for run_matlab.m.

MATLAB's jsondecode cannot tell a one-element array from a scalar, turns arrays
of objects into struct arrays and null into [], so every argument value is
written as {"t": type, "v": value}:

    str, num, bool, null       scalars
    obj                        "v" is a list of {"k": key, "v": tagged} pairs
    array                      plain JSON array; run_matlab.m maps it to a
                               string array, numeric or logical row vector, or
                               a cell array (for example a cell array of structs)
    cell                       {"$list": [...]}: always a cell array

The mock response rules are embedded as ready-to-send JSON text
("control_json") so MATLAB never re-encodes them.

matlab_calling.json can list parameters that the MATLAB library takes
positionally instead of as name=value pairs, keyed "<target>.<method>".
"""

import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))


def tag(v):
    if isinstance(v, bool):
        return {"t": "bool", "v": v}
    if isinstance(v, (int, float)):
        return {"t": "num", "v": v}
    if isinstance(v, str):
        return {"t": "str", "v": v}
    if v is None:
        return {"t": "null", "v": None}
    if isinstance(v, dict):
        if set(v) == {"$list"}:
            return {"t": "cell", "v": [tag(x) for x in v["$list"]]}
        return {"t": "obj", "v": [{"k": k, "v": tag(x)} for k, x in v.items()]}
    if isinstance(v, list):
        return {"t": "array", "v": [tag(x) for x in v]}
    raise TypeError(type(v))


def main():
    with open(os.path.join(HERE, "scenarios.json"), encoding="utf-8") as fh:
        doc = json.load(fh)
    calling_path = os.path.join(HERE, "matlab_calling.json")
    positional = {}
    if os.path.exists(calling_path):
        with open(calling_path, encoding="utf-8") as fh:
            positional = json.load(fh).get("positional", {})
    out = []
    for sc in doc["scenarios"]:
        key = "%s.%s" % (sc.get("target", "api"), sc["method"])
        out.append({
            "id": sc["id"],
            "target": sc.get("target", "api"),
            "method": sc["method"],
            "property": bool(sc.get("property")),
            "positional": [{"name": p} for p in positional.get(key, [])],
            "args": tag(sc.get("args") or {}),
            "client": tag(sc.get("client") or {}),
            "strategy": tag(sc.get("strategy") or {}),
            "control_json": json.dumps({"id": sc["id"], "rules": sc.get("rules") or []}),
        })
    target = os.path.join(HERE, "scenarios.matlab.json")
    with open(target, "w", encoding="utf-8", newline="\n") as fh:
        json.dump({"api_key": doc["api_key"], "scenarios": out}, fh, ensure_ascii=True)
    print("wrote %s (%d scenarios)" % (target, len(out)))


if __name__ == "__main__":
    main()

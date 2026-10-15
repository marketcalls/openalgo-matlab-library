#!/usr/bin/env python3
"""Compare R and MATLAB parity outputs against the Python reference.

Usage:
    python compare.py                  compare every candidate output present in out/
    python compare.py --lang r         compare only R
    python compare.py --require r      fail if out/r.json is missing
    python compare.py --only gtt.      restrict to scenario ids containing the text
    python compare.py -v               also list passing scenarios

For each scenario the comparison checks:
  * requests: count, then per request the method, path, query parameters,
    Content-Type media type (parameters such as charset are ignored) and the
    body. JSON bodies are compared semantically and type-sensitively: a string
    never equals a number, a boolean never equals a number, null only equals
    null, and 1 equals 1.0. Non-JSON bodies are compared as text.
  * outcome: whether the call raised; if both raised, the message; otherwise
    the normalized return value with the same JSON equality. Tables (data
    frames, timetables) are compared by column set, row count, per-column
    time zone and records.
  * warnings: only the number of warnings issued.

Differences listed in allowlist.json (each with a reason) are reported as
ALLOWED instead of FAIL. Exit status: 0 when every compared scenario passes,
1 on any failure or missing scenario, 2 when there is nothing to compare.
"""

import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
MISSING = "<missing>"
LANGS = ("r", "matlab")


def load(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def is_num(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def show(v):
    if v is MISSING:
        return MISSING
    s = json.dumps(v, ensure_ascii=True)
    return s if len(s) <= 300 else s[:297] + "..."


def replace_bases(value, meta):
    """Replace the run-specific mock URLs inside strings with stable placeholders."""
    pairs = [(meta.get("mock_base"), "$MOCK"), (meta.get("closed_base"), "$CLOSED")]
    if isinstance(value, str):
        for old, new in pairs:
            if old:
                value = value.replace(old, new)
        return value
    if isinstance(value, dict):
        return {k: replace_bases(v, meta) for k, v in value.items()}
    if isinstance(value, list):
        return [replace_bases(v, meta) for v in value]
    return value


def jdiff(exp, act, path, out):
    """Append (path, expected, actual) for every difference."""
    if isinstance(exp, bool) or isinstance(act, bool):
        if not (isinstance(exp, bool) and isinstance(act, bool) and exp == act):
            out.append((path, exp, act))
        return
    if is_num(exp) and is_num(act):
        if float(exp) != float(act):
            out.append((path, exp, act))
        return
    if isinstance(exp, dict) and isinstance(act, dict):
        if exp.get("__type__") == "table" or act.get("__type__") == "table":
            return table_diff(exp, act, path, out)
        for k in list(exp) + [k for k in act if k not in exp]:
            if k not in act:
                out.append(("%s.%s" % (path, k), exp[k], MISSING))
            elif k not in exp:
                out.append(("%s.%s" % (path, k), MISSING, act[k]))
            else:
                jdiff(exp[k], act[k], "%s.%s" % (path, k), out)
        return
    if isinstance(exp, list) and isinstance(act, list):
        if len(exp) != len(act):
            out.append((path + ".length", len(exp), len(act)))
        for i in range(min(len(exp), len(act))):
            jdiff(exp[i], act[i], "%s[%d]" % (path, i), out)
        return
    if type(exp) is not type(act) or exp != act:
        out.append((path, exp, act))


def table_diff(exp, act, path, out):
    if exp.get("__type__") != act.get("__type__"):
        out.append((path + ".__type__", exp.get("__type__", MISSING), act.get("__type__", MISSING)))
        return
    ecols, acols = exp.get("columns", []), act.get("columns", [])
    if set(ecols) != set(acols):
        out.append((path + ".columns", sorted(ecols), sorted(acols)))
    if exp.get("nrow") != act.get("nrow"):
        out.append((path + ".nrow", exp.get("nrow"), act.get("nrow")))
    etz, atz = exp.get("tz") or {}, act.get("tz") or {}
    for col in list(etz) + [c for c in atz if c not in etz]:
        jdiff(etz.get(col, MISSING), atz.get(col, MISSING), "%s.tz.%s" % (path, col), out)
    erec, arec = exp.get("records", []), act.get("records", [])
    for i in range(min(len(erec), len(arec))):
        jdiff(erec[i], arec[i], "%s.records[%d]" % (path, i), out)


def media_type(ct):
    return ct.split(";")[0].strip().lower() if ct else None


def request_diffs(ereqs, areqs, out):
    if len(ereqs) != len(areqs):
        out.append(("requests.count", len(ereqs), len(areqs)))
    for i in range(min(len(ereqs), len(areqs))):
        e, a, p = ereqs[i], areqs[i], "requests[%d]" % i
        for key in ("method", "path"):
            if e.get(key) != a.get(key):
                out.append(("%s.%s" % (p, key), e.get(key), a.get(key)))
        jdiff(e.get("query") or {}, a.get("query") or {}, p + ".query", out)
        if media_type(e.get("content_type")) != media_type(a.get("content_type")):
            out.append((p + ".content_type", e.get("content_type"), a.get("content_type")))
        if e.get("body_is_json") and a.get("body_is_json"):
            jdiff(e.get("body"), a.get("body"), p + ".body", out)
        elif e.get("body_is_json") != a.get("body_is_json"):
            out.append((p + ".body_is_json", e.get("body_is_json"), a.get("body_is_json")))
        elif (e.get("body_raw") or "") != (a.get("body_raw") or ""):
            out.append((p + ".body_raw", e.get("body_raw"), a.get("body_raw")))


def scenario_diffs(ref, cand, ref_meta, cand_meta):
    out = []
    request_diffs(ref.get("requests") or [], cand.get("requests") or [], out)
    eo = replace_bases(ref["outcome"], ref_meta)
    ao = replace_bases(cand.get("outcome") or {}, cand_meta)
    if bool(eo.get("raised")) != bool(ao.get("raised")):
        out.append(("outcome.raised", eo.get("raised"),
                    "%s (%s)" % (ao.get("raised"), ao.get("message") if ao.get("raised") else
                                 show(ao.get("value")))))
    elif eo.get("raised"):
        if eo.get("message") != ao.get("message"):
            out.append(("outcome.message", eo.get("message"), ao.get("message")))
    else:
        jdiff(eo.get("value"), ao.get("value"), "outcome.value", out)
    ew, aw = len(ref.get("warnings") or []), len(cand.get("warnings") or [])
    if ew != aw:
        out.append(("warnings.count", ew, aw))
    return out


def glob_re(pattern):
    return re.compile("^" + ".*".join(re.escape(p) for p in pattern.split("*")) + "$")


UTC_NAMES = {"UTC", "GMT", "Etc/UTC", "Etc/GMT", "Z"}
# IANA links: the same zone under its current and its legacy name.
TZ_ALIASES = {"Asia/Kolkata": "Asia/Calcutta"}


def jsondecode_equivalent(exp, act):
    """Equal after MATLAB jsondecode's lossy mapping, and in no other way.

    Two collapses are accepted, recursively: JSON null decodes to [] (an empty
    array), and a one-element array of objects decodes to a 1x1 struct, which
    MATLAB cannot tell apart from a single object. Everything else (strings,
    numbers, keys, other array lengths) must still be equal.
    """
    if exp is None:
        return act is None or act == []
    if isinstance(exp, list) and len(exp) == 1 and isinstance(exp[0], dict) and isinstance(act, dict):
        return jsondecode_equivalent(exp[0], act)
    if isinstance(exp, dict) and isinstance(act, dict):
        if set(exp) != set(act):
            return False
        return all(jsondecode_equivalent(exp[k], act[k]) for k in exp)
    if isinstance(exp, list) and isinstance(act, list):
        return len(exp) == len(act) and all(jsondecode_equivalent(e, a) for e, a in zip(exp, act))
    diffs = []
    jdiff(exp, act, "", diffs)
    return not diffs


def predicate_ok(pred, exp, act):
    if pred in (None, "any"):
        return True
    if pred == "nonempty_string":
        return isinstance(act, str) and act.strip() != ""
    if pred == "naive_as_utc":
        if exp is None and isinstance(act, str) and act in UTC_NAMES:
            return True
        return (isinstance(exp, str) and isinstance(act, str)
                and act in (exp + "+00:00", exp + "Z"))
    if pred == "tz_alias":
        if not (isinstance(exp, str) and isinstance(act, str)):
            return False
        return exp == act or TZ_ALIASES.get(exp) == act or TZ_ALIASES.get(act) == exp
    if pred == "jsondecode_equivalent":
        return jsondecode_equivalent(exp, act)
    if isinstance(pred, dict) and "regex" in pred:
        return isinstance(act, str) and re.search(pred["regex"], act) is not None
    raise ValueError("unknown allowlist predicate %r" % (pred,))


class Allowlist:
    def __init__(self, path):
        self.rules = load(path)["rules"] if os.path.exists(path) else []
        for r in self.rules:
            r["_scen"] = [glob_re(s) for s in r["scenarios"]]
            r["_paths"] = [glob_re(p) for p in r["paths"]]
            r["_used"] = set()

    def match(self, lang, scenario, path, exp, act):
        for r in self.rules:
            if lang not in r.get("langs", LANGS):
                continue
            if not any(rx.match(scenario) for rx in r["_scen"]):
                continue
            if not any(rx.match(path) for rx in r["_paths"]):
                continue
            if predicate_ok(r.get("predicate"), exp, act):
                r["_used"].add(lang)
                return r
        return None


def dynamic_ok(scenario, path, exp, act):
    for d in scenario.get("dynamic") or []:
        if d["path"] == path:
            rx = re.compile(d["regex"])
            return all(isinstance(v, str) and rx.search(v) for v in (exp, act))
    return False


def compare_lang(lang, ref, cand, scenarios, allow, only, verbose):
    counts = {"PASS": 0, "ALLOWED": 0, "FAIL": 0, "MISSING": 0}
    report = []
    print("=" * 78)
    print("%s vs Python reference" % lang.upper())
    print("  reference: %s, %s" % (ref["meta"].get("runtime"), ref["meta"].get("generated")))
    print("  candidate: %s, %s" % (cand["meta"].get("runtime"), cand["meta"].get("generated")))
    print("-" * 78)
    for sc in scenarios:
        sid = sc["id"]
        if only and only not in sid:
            continue
        if sid not in ref["results"]:
            print("SKIP     %s (not in reference output; rerun run_python.py)" % sid)
            continue
        if sid not in cand["results"]:
            counts["MISSING"] += 1
            print("MISSING  %s" % sid)
            report.append({"id": sid, "status": "MISSING"})
            continue
        diffs = scenario_diffs(ref["results"][sid], cand["results"][sid], ref["meta"], cand["meta"])
        fails, allowed = [], []
        for path, exp, act in diffs:
            if dynamic_ok(sc, path, exp, act):
                continue
            rule = allow.match(lang, sid, path, exp, act)
            (allowed if rule else fails).append((path, exp, act, rule))
        status = "FAIL" if fails else ("ALLOWED" if allowed else "PASS")
        counts[status] += 1
        report.append({"id": sid, "status": status,
                       "fails": [{"path": p, "expected": e, "actual": a} for p, e, a, _ in fails],
                       "allowed": [{"path": p, "expected": e, "actual": a, "rule": r["id"]}
                                   for p, e, a, r in allowed]})
        if status == "PASS" and not verbose:
            continue
        print("%-8s %s" % (status, sid))
        for p, e, a, _ in fails:
            print("    %s\n        expected: %s\n        actual:   %s" % (p, show(e), show(a)))
        for p, e, a, r in allowed:
            print("    [allowed: %s] %s\n        expected: %s\n        actual:   %s"
                  % (r["id"], p, show(e), show(a)))
    print("-" * 78)
    print("%s: %d pass, %d allowed, %d fail, %d missing"
          % (lang.upper(), counts["PASS"], counts["ALLOWED"], counts["FAIL"], counts["MISSING"]))
    with open(os.path.join(OUT, "compare_%s.json" % lang), "w", encoding="utf-8") as fh:
        json.dump({"lang": lang, "counts": counts, "scenarios": report}, fh, indent=1,
                  ensure_ascii=False, default=str)
    return counts["FAIL"] == 0 and counts["MISSING"] == 0


def main():
    try:
        sys.stdout.reconfigure(errors="backslashreplace")
    except AttributeError:
        pass
    ap = argparse.ArgumentParser(description="Compare parity outputs against Python.")
    ap.add_argument("--lang", choices=LANGS + ("all",), default="all")
    ap.add_argument("--require", action="append", default=[], choices=LANGS)
    ap.add_argument("--only")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    ref_path = os.path.join(OUT, "python.json")
    if not os.path.exists(ref_path):
        print("No reference output: run `python run_python.py` first.")
        return 2
    ref = load(ref_path)
    scenarios = load(os.path.join(HERE, "scenarios.json"))["scenarios"]
    allow = Allowlist(os.path.join(HERE, "allowlist.json"))

    langs = LANGS if args.lang == "all" else (args.lang,)
    ok, compared = True, 0
    for lang in langs:
        path = os.path.join(OUT, "%s.json" % lang)
        if not os.path.exists(path):
            msg = "%s: no output at %s" % (lang.upper(), path)
            if lang in args.require or args.lang == lang:
                print(msg + " -> FAIL")
                ok = False
            else:
                print(msg + " -> skipped")
            continue
        compared += 1
        ok = compare_lang(lang, ref, load(path), scenarios, allow, args.only, args.verbose) and ok

    unused = [r["id"] for r in allow.rules if not r["_used"]]
    if compared and unused and not args.only:
        print("Allowlist rules not used in this run: %s" % ", ".join(unused))
    if compared == 0 and ok:
        print("Nothing to compare.")
        return 2
    print("OVERALL: %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

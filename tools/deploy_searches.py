#!/usr/bin/env python3
"""Idempotently deploy the SPL saved searches to the local Splunk REST API.

Runs ON the Splunk host (via SSM Run Command). Talks only to https://127.0.0.1:8089; port 8089
is never exposed. Default is a dry run. Searches are created DISABLED unless --enable is given.

    deploy_searches.py --repo-root . [--apply] [--enable] [--report out.json]

Password: env SPLUNK_PASSWORD, else SSM SecureString named by --password-param (via `aws` CLI).
It is held in memory only and never printed.
"""
import argparse
import base64
import hashlib
import json
import os
import re
import ssl
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

import yaml

REQUIRED_APPS = ("Splunk_TA_windows", "Splunk_TA_nix")
PLACEHOLDER_RE = re.compile(r"<.*@example\.com>|example\.com")
# (label, SPL run over the last 24h, field that must be non-empty)
FIELD_CHECKS = [
    ("windows EventCode", 'index=windows_endpoint source="XmlWinEventLog:Security" EventCode=4625', ["EventCode", "TargetUserName", "IpAddress"]),
    ("linux auditd", "index IN (linux_endpoint, linux_audit) sourcetype=linux_audit type=USER_AUTH", ["acct", "addr", "host"]),
]


class DeployError(Exception):
    pass


def load_manifest(root):
    with open(os.path.join(root, "detections/deployment.yml")) as f:
        m = yaml.safe_load(f)
    defaults, rules = m.get("defaults", {}), m.get("rules", {})
    out = {}
    for rid, r in rules.items():
        merged = {**defaults, **r}
        merged["email"] = {**defaults.get("email", {}), **r.get("email", {})}
        with open(os.path.join(root, merged["spl"])) as f:
            merged["spl_text"] = f.read().strip()
        merged["spl_sha256"] = hashlib.sha256(merged["spl_text"].encode()).hexdigest()
        out[rid] = merged
    return out


def validate(root, rules):
    problems = []
    spl_dir = os.path.join(root, "detections/spl")
    on_disk = {f"detections/spl/{f}" for f in os.listdir(spl_dir) if f.endswith(".spl")}
    listed = {r["spl"] for r in rules.values()}
    if on_disk != listed:
        problems.append(f"manifest/SPL mismatch: unlisted={sorted(on_disk - listed)} missing={sorted(listed - on_disk)}")
    for rid, r in rules.items():
        if not r["spl_text"]:
            problems.append(f"{rid}: empty SPL")
        if r["email"].get("enabled") and (not r["email"].get("to") or PLACEHOLDER_RE.search(r["email"]["to"])):
            problems.append(f"{rid}: email enabled with placeholder/empty recipient")
    names = [r["name"] for r in rules.values()]
    if len(set(names)) != len(names):
        problems.append("duplicate saved-search names")
    return problems


def search_param(spl):
    return spl if spl.startswith(("search ", "|")) else "search " + spl


def build_params(r, enable):
    p = {
        "search": search_param(r["spl_text"]),
        "is_scheduled": "1",
        "cron_schedule": r["cron_schedule"],
        "dispatch.earliest_time": r["earliest"],
        "dispatch.latest_time": r["latest"],
        "alert_type": "number of events",
        "alert_comparator": r["alert_comparator"],
        "alert_threshold": str(r["alert_threshold"]),
        "alert.track": "1" if r["alert_track"] else "0",
        "alert.severity": str(r["severity"]),
        "description": f"Managed by deploy_searches.py; spl_sha256={r['spl_sha256']}",
        "disabled": "0" if enable else "1",
    }
    email = r["email"]
    if email.get("enabled"):
        p["action.email"] = "1"
        p["action.email.to"] = email["to"]
    else:
        p["action.email"] = "0"
    return p


class Splunk:
    def __init__(self, base, user, password):
        self.base = base.rstrip("/")
        host = urllib.parse.urlparse(self.base).hostname
        if host not in ("127.0.0.1", "localhost", "::1"):
            raise DeployError("refusing non-loopback Splunk URL; run this on the Splunk host")
        # Self-signed management cert; loopback only, so verification is skipped deliberately.
        self.ctx = ssl.create_default_context()
        self.ctx.check_hostname = False
        self.ctx.verify_mode = ssl.CERT_NONE
        self.auth = "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()

    def request(self, method, path, data=None):
        url = self.base + path
        body = urllib.parse.urlencode(data).encode() if data is not None else None
        req = urllib.request.Request(url, data=body, method=method, headers={"Authorization": self.auth})
        try:
            with urllib.request.urlopen(req, context=self.ctx, timeout=60) as resp:
                return resp.status, resp.read().decode()
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode(errors="replace")[:500]
        except urllib.error.URLError as e:
            raise DeployError(f"cannot reach Splunk at {self.base}: {e.reason}")

    def get_json(self, path):
        sep = "&" if "?" in path else "?"
        status, text = self.request("GET", path + sep + "output_mode=json&count=0")
        return status, (json.loads(text) if status == 200 else text)


def preflight(sp, skip_fields):
    errs = []
    status, info = sp.get_json("/services/server/info")
    if status != 200:
        raise DeployError(f"Splunk health check failed (HTTP {status})")
    status, apps = sp.get_json("/services/apps/local")
    have = {e["name"] for e in apps["entry"]} if status == 200 else set()
    for a in REQUIRED_APPS:
        if a not in have:
            errs.append(f"add-on missing: {a}")
    if skip_fields:
        return errs
    for label, spl, fields in FIELD_CHECKS:
        agg = ", ".join(f"count({f}) AS {f}" for f in fields)
        q = f"search {spl} | stats count AS events, {agg}"
        status, text = sp.request("POST", "/services/search/jobs/export",
                                  {"search": q, "earliest_time": "-24h", "output_mode": "json"})
        row = {}
        for line in text.splitlines():
            try:
                row = json.loads(line).get("result", row)
            except ValueError:
                pass
        if status != 200 or not row or int(row.get("events", 0)) == 0:
            errs.append(f"{label}: no events in last 24h (cannot verify field extraction)")
            continue
        for f in fields:
            if int(row.get(f, 0)) == 0:
                errs.append(f"{label}: field '{f}' is empty on all events")
    return errs


def upsert(sp, r, enable):
    ns = f"/servicesNS/nobody/{r['app']}/saved/searches"
    ent = f"{ns}/{urllib.parse.quote(r['name'], safe='')}"
    params = build_params(r, enable)
    status, _ = sp.get_json(ent)
    if status == 200:
        action = "updated"
        st, text = sp.request("POST", ent, params)
    elif status == 404:
        action = "created"
        st, text = sp.request("POST", ns, {"name": r["name"], **params})
    else:
        return {"status": "error", "error": f"lookup HTTP {status}"}
    if st not in (200, 201):
        return {"status": "error", "error": f"HTTP {st}: {text[:300]}"}
    # Read back to confirm the stored state.
    st, doc = sp.get_json(ent)
    if st != 200:
        return {"status": "error", "error": f"read-back HTTP {st}"}
    c = doc["entry"][0]["content"]
    ok = (c.get("cron_schedule") == r["cron_schedule"] and c.get("dispatch.earliest_time") == r["earliest"]
          and str(c.get("disabled")) in (("0", "False", "false") if enable else ("1", "True", "true")))
    return {"status": action if ok else "error", "disabled": c.get("disabled"),
            **({} if ok else {"error": "read-back does not match requested settings"})}


def get_password(args):
    if os.environ.get("SPLUNK_PASSWORD"):
        return os.environ["SPLUNK_PASSWORD"]
    if not args.password_param:
        raise DeployError("set SPLUNK_PASSWORD or pass --password-param")
    cmd = ["aws", "ssm", "get-parameter", "--name", args.password_param, "--with-decryption",
           "--query", "Parameter.Value", "--output", "text"]
    if args.region:
        cmd += ["--region", args.region]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise DeployError("could not read the Splunk password from SSM")  # stderr withheld deliberately
    return res.stdout.strip()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--splunk-url", default="https://127.0.0.1:8089")
    ap.add_argument("--user", default="admin")
    ap.add_argument("--password-param")
    ap.add_argument("--region")
    ap.add_argument("--apply", action="store_true", help="write to Splunk (default: dry run)")
    ap.add_argument("--enable", action="store_true", help="enable searches (default: create/keep disabled)")
    ap.add_argument("--skip-field-preflight", action="store_true")
    ap.add_argument("--report")
    args = ap.parse_args(argv)

    rules = load_manifest(args.repo_root)
    problems = validate(args.repo_root, rules)
    if problems:
        print("manifest validation failed:\n  " + "\n  ".join(problems), file=sys.stderr)
        return 2

    report = {"mode": "apply" if args.apply else "dry-run", "enable": args.enable, "rules": {}}
    if not args.apply:
        for rid, r in rules.items():
            report["rules"][rid] = {"name": r["name"], "spl_sha256": r["spl_sha256"], "status": "planned",
                                    "params": {k: v for k, v in build_params(r, args.enable).items() if k != "search"}}
    else:
        sp = Splunk(args.splunk_url, args.user, get_password(args))
        errs = preflight(sp, args.skip_field_preflight)
        if errs:
            report["preflight_errors"] = errs
            print("preflight failed:\n  " + "\n  ".join(errs), file=sys.stderr)
        else:
            for rid, r in rules.items():
                res = upsert(sp, r, args.enable)
                report["rules"][rid] = {"name": r["name"], "spl_sha256": r["spl_sha256"], **res}
    text = json.dumps(report, indent=2)
    if args.report:
        with open(args.report, "w") as f:
            f.write(text)
    print(text)
    failed = report.get("preflight_errors") or any(v["status"] == "error" for v in report["rules"].values())
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except DeployError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)

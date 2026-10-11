"""Tests for the deploy client using a mock Splunk REST server. Run: python3 -m unittest discover tests"""
import json
import os
import sys
import threading
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import deploy_sigma_searches as d  # noqa: E402

STORE = {}


class Mock(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        p = urllib.parse.urlparse(self.path).path
        if p == "/services/server/info":
            return self._send(200, {})
        if p == "/services/apps/local":
            return self._send(200, {"entry": [{"name": "Splunk_TA_windows"}, {"name": "Splunk_TA_nix"}]})
        name = urllib.parse.unquote(p.rsplit("/", 1)[-1])
        if name in STORE:
            return self._send(200, {"entry": [{"content": STORE[name]}]})
        self._send(404, {})

    def do_POST(self):
        p = urllib.parse.urlparse(self.path).path
        form = dict(urllib.parse.parse_qsl(self.rfile.read(int(self.headers["Content-Length"])).decode()))
        if p == "/services/search/jobs/export":
            row = {"events": "10", "EventCode": "10", "TargetUserName": "10", "IpAddress": "10",
                   "acct": "10", "addr": "10", "host": "10"}
            self.send_response(200)
            self.end_headers()
            self.wfile.write(json.dumps({"result": row}).encode())
            return
        if p.endswith("/saved/searches"):
            name = form.pop("name")
            STORE[name] = form
            return self._send(201, {})
        name = urllib.parse.unquote(p.rsplit("/", 1)[-1])
        STORE[name].update(form)
        self._send(200, {})


class DeployTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = HTTPServer(("127.0.0.1", 0), Mock)
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()
        cls.url = f"http://127.0.0.1:{cls.srv.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()

    def run_main(self, *extra):
        os.environ["SPLUNK_PASSWORD"] = "test-only"
        return d.main(["--repo-root", ROOT, "--splunk-url", self.url, *extra])

    def test_manifest_covers_all_six_rules(self):
        rules = d.load_manifest(ROOT)
        self.assertEqual(len(rules), 6)
        self.assertEqual(d.validate(ROOT, rules), [])

    def test_dry_run_writes_nothing(self):
        STORE.clear()
        self.assertEqual(d.main(["--repo-root", ROOT]), 0)
        self.assertEqual(STORE, {})

    def test_apply_creates_disabled_then_is_idempotent(self):
        STORE.clear()
        self.assertEqual(self.run_main("--apply"), 0)
        self.assertEqual(len(STORE), 6)
        self.assertTrue(all(v["disabled"] == "1" and v["action.email"] == "0" and v["alert.track"] == "1"
                            for v in STORE.values()))
        self.assertEqual(self.run_main("--apply"), 0)
        self.assertEqual(len(STORE), 6)  # no duplicates
        self.assertEqual(self.run_main("--apply", "--enable"), 0)
        self.assertTrue(all(v["disabled"] == "0" for v in STORE.values()))

    def test_windows_spray_schedule(self):
        STORE.clear()
        self.assertEqual(self.run_main("--apply"), 0)
        v = STORE["Sigma - Windows Password Spray From One Source"]
        self.assertEqual((v["cron_schedule"], v["dispatch.earliest_time"]), ("*/1 * * * *", "-10m"))
        self.assertIn("dc(TargetUserName)", v["search"])

    def test_email_placeholder_rejected(self):
        rules = d.load_manifest(ROOT)
        r = next(iter(rules.values()))
        r["email"]["enabled"] = True
        self.assertTrue(any("placeholder" in p for p in d.validate(ROOT, rules)))

    def test_refuses_non_loopback(self):
        with self.assertRaises(d.DeployError):
            d.Splunk("https://10.0.0.5:8089", "a", "b")


if __name__ == "__main__":
    unittest.main()

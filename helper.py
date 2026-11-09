"""helper.py - local bridge between the backdoor "Installer Control" tile and the master kit (2026-11-09).

Run on Chad's PC:   python -I helper.py        (listens on http://127.0.0.1:8754 only)
Pairing: on first start it writes a token to %USERPROFILE%\\.waov-keys\\helper-token.txt and prints it.
         The backdoor tile sends it in the X-WAOV-Token header. No token = 403. No Claude API here.

GET  /kit            -> {version, text, path, released}        the master .ps1 and its version (the file mirror)
POST /save           {text, notes, dryRun?}                    writes the master .ps1, runs release-kit.ps1 -Bump,
                     -> {ok, previous, version, liveVersion, sha256, text}   then reads the file back from disk
Only origins https://waov.art, https://www.waov.art and http://localhost / 127.0.0.1 may call it.
"""
import json, os, re, secrets, subprocess, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.abspath(__file__))
PS1 = os.path.join(ROOT, "launcher", "Miles Installer and Updater.ps1")
KEYS = os.path.join(os.environ["USERPROFILE"], ".waov-keys")
TOKEN_FILE = os.path.join(KEYS, "helper-token.txt")
LATEST = "https://github.com/cdowns78999/waov-installer/releases/latest/download/latest.json"
PORT = 8754
ALLOWED = re.compile(r"^(https://(www\.)?waov\.art|http://(localhost|127\.0\.0\.1)(:\d+)?)$")
VER = re.compile(r"(?m)^\$KitVersion = '([\d\.]+)'")


def token():
    os.makedirs(KEYS, exist_ok=True)
    if not os.path.exists(TOKEN_FILE):
        with open(TOKEN_FILE, "w") as f:
            f.write(secrets.token_urlsafe(24))
    return open(TOKEN_FILE).read().strip()


def read_kit():
    text = open(PS1, encoding="utf-8-sig").read()
    m = VER.search(text)
    return text, (m.group(1) if m else "?")


def released():
    try:
        with urllib.request.urlopen(LATEST, timeout=8) as r:
            return json.load(r).get("version", "")
    except Exception:
        return ""


class H(BaseHTTPRequestHandler):
    def cors(self):
        o = self.headers.get("Origin", "")
        if ALLOWED.match(o):
            self.send_header("Access-Control-Allow-Origin", o)
            self.send_header("Vary", "Origin")
            self.send_header("Access-Control-Allow-Headers", "Content-Type, X-WAOV-Token")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Private-Network", "true")

    def reply(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code); self.cors()
        self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body)))
        self.end_headers(); self.wfile.write(body)

    def ok_caller(self):
        o = self.headers.get("Origin", "")
        if o and not ALLOWED.match(o):
            self.reply(403, {"ok": False, "error": "origin not allowed"}); return False
        if self.headers.get("X-WAOV-Token", "") != TOKEN:
            self.reply(403, {"ok": False, "error": "pairing token missing or wrong"}); return False
        return True

    def do_OPTIONS(self):
        self.send_response(204); self.cors(); self.end_headers()

    def do_GET(self):
        if self.path != "/kit":
            return self.reply(404, {"ok": False})
        if not self.ok_caller():
            return
        text, v = read_kit()
        self.reply(200, {"ok": True, "version": v, "text": text, "path": PS1, "released": released()})

    def do_POST(self):
        if self.path != "/save":
            return self.reply(404, {"ok": False})
        if not self.ok_caller():
            return
        try:
            n = int(self.headers.get("Content-Length", "0"))
            req = json.loads(self.rfile.read(n) or b"{}")
            new = req.get("text", "")
            if not VER.search(new) or "param(" not in new:
                return self.reply(400, {"ok": False, "error": "text is not the installer script (no KitVersion or param block)"})
            _, before = read_kit()
            backup = PS1 + ".last-save"
            with open(PS1, encoding="utf-8-sig") as f, open(backup, "w", encoding="utf-8") as b:
                b.write(f.read())
            with open(PS1, "w", encoding="utf-8-sig", newline="") as f:
                f.write(new.replace("\r\n", "\n").replace("\n", "\r\n"))
            args = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", os.path.join(ROOT, "release-kit.ps1"),
                    "-Bump", "-Notes", (req.get("notes") or "backdoor save")[:200]]
            if req.get("dryRun"):
                args.append("-DryRun")
            p = subprocess.run(args, capture_output=True, text=True, timeout=600, cwd=ROOT)
            last = (p.stdout.strip().splitlines() or ["{}"])[-1]
            if p.returncode != 0 or not last.startswith("{"):
                with open(backup, encoding="utf-8") as b, open(PS1, "w", encoding="utf-8") as f:
                    f.write(b.read())
                return self.reply(500, {"ok": False, "error": "release failed, master restored", "detail": (p.stderr or p.stdout)[-800:]})
            res = json.loads(last)
            text, v = read_kit()   # read back from disk: the mirror refreshes from the file, not from what was sent
            res.update({"ok": True, "before": before, "fileVersion": v, "text": text})
            self.reply(200, res)
        except Exception as e:
            self.reply(500, {"ok": False, "error": str(e)})

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    TOKEN = token()
    print(f"WAOV installer helper on http://127.0.0.1:{PORT}  (pairing token in {TOKEN_FILE})")
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()

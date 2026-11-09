"""helper.py - the PC side of the backdoor Installer Control tile (2026-11-09).

Run on Chad's PC and leave it open:   python -I helper.py
What it does, forever, every few seconds:
  1. Sends the master script (launcher\\Miles Installer and Updater.ps1) to waov.art. That is also its heartbeat,
     so the tile shows "PC helper online".
  2. Asks waov.art for a queued update (made by PREPARE, then PROCEED WITH PLAN in the backdoor).
  3. Runs it with live rows the tile shows as its loading screen:
       backup   ALWAYS one backup per update: backups\\{time}-v{old}.ps1   (never skipped)
       write    the prepared script becomes the master
       build    release-kit.ps1 -Bump: exe and bat rebuilt
       sign     SHA-256 + RSA signature
       push     git push to waov-installer
       release  GitHub release v{new} with latest.json
       live     latest.json read back from GitHub
     Any failure before "push": the master is restored from the backup and nothing is published.
     A failure after "push": the master stays (git has it) and the tile says to retry the release.
Every call to waov.art is signed with the kit private key (%USERPROFILE%\\.waov-keys), so no extra secret is needed.
No Claude API here: PREPARE runs on waov.art.
"""
import base64, datetime, json, os, re, shutil, subprocess, sys, time, urllib.request, xml.etree.ElementTree as ET
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, rsa

ROOT = os.path.dirname(os.path.abspath(__file__))
PS1 = os.path.join(ROOT, "launcher", "Miles Installer and Updater.ps1")
BACKUPS = os.path.join(ROOT, "backups")
PRIV = os.path.join(os.environ["USERPROFILE"], ".waov-keys", "waov-update.private.xml")
API = os.environ.get("WAOV_IC_URL", "https://waov.art/.netlify/functions/installer-control")
VER = re.compile(r"(?m)^\$KitVersion = '([\d\.]+)'")
STEP = re.compile(r"^STEP:(\w+)\s*(.*)$")


def load_key():
    x = ET.parse(PRIV).getroot()
    n = lambda tag: int.from_bytes(base64.b64decode(x.find(tag).text), "big")
    pub = rsa.RSAPublicNumbers(n("Exponent"), n("Modulus"))
    return rsa.RSAPrivateNumbers(n("P"), n("Q"), n("D"), n("DP"), n("DQ"), n("InverseQ"), pub).private_key()


KEY = load_key()


def call(op, **fields):
    fields["ts"] = int(time.time() * 1000)
    payload = json.dumps(fields)
    sig = base64.b64encode(KEY.sign(payload.encode(), padding.PKCS1v15(), hashes.SHA256())).decode()
    req = urllib.request.Request(API, data=json.dumps({"op": op, "payload": payload, "sig": sig}).encode(),
                                 headers={"Content-Type": "application/json", "User-Agent": "WAOV-Helper"}, method="POST")
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def master():
    return open(PS1, encoding="utf-8-sig").read()


def progress(job, row, state, field="", **extra):
    try:
        call("helper.progress", jobId=job, row=row, state=state, field=field, **extra)
    except Exception as e:
        print("  progress post failed:", e)


def run_job(job):
    jid, old = job["jobId"], job["from"]
    print(f"[{datetime.datetime.now():%H:%M:%S}] job {jid}: v{old} -> v{job['to']}")
    # 1 backup (always, one per update)
    os.makedirs(BACKUPS, exist_ok=True)
    backup = os.path.join(BACKUPS, f"{datetime.datetime.now():%Y%m%d-%H%M%S}-v{old}.ps1")
    progress(jid, "backup", "run", "making the backup")
    shutil.copy2(PS1, backup)
    progress(jid, "backup", "ok", os.path.basename(backup))
    # 2 write
    progress(jid, "write", "run", "updating the master file")
    text = job["script"]
    if not VER.search(text) or "Invoke-UpdateCheck" not in text:
        progress(jid, "write", "fail", "", fail="the prepared script is missing the version line or the update check", restored=True, done=True)
        return
    with open(PS1, "w", encoding="utf-8-sig", newline="") as f:
        f.write(text.replace("\r\n", "\n").replace("\n", "\r\n"))
    progress(jid, "write", "ok", f"{len(text.splitlines())} lines written")
    # 3-7 release-kit with live rows
    rows = ["build", "sign", "push", "release", "live"]
    progress(jid, "build", "run", "building the exe and bat")
    p = subprocess.Popen(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                          os.path.join(ROOT, "release-kit.ps1"), "-Bump", "-Notes", job.get("notes") or "backdoor update"],
                         cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    done_rows = []
    for line in p.stdout:
        m = STEP.match(line.strip())
        if m and m.group(1) in rows:
            row = m.group(1)
            progress(jid, row, "ok", m.group(2))
            done_rows.append(row)
            nxt = rows[rows.index(row) + 1] if rows.index(row) + 1 < len(rows) else None
            if nxt:
                progress(jid, nxt, "run", {"sign": "signing", "push": "syncing to GitHub", "release": "publishing the release",
                                           "live": "checking GitHub"}[nxt])
    err = p.stderr.read()
    p.wait()
    if p.returncode != 0 or "live" not in done_rows:
        failed = next(r for r in rows if r not in done_rows)
        reason = (err.strip().splitlines() or ["release-kit stopped"])[-1][:300]
        if "push" in done_rows:
            progress(jid, failed, "fail", "", fail=reason + " (pushed to GitHub, master kept: retry the release)", restored=False, done=True)
        else:
            shutil.copy2(backup, PS1)
            progress(jid, failed, "fail", "", fail=reason + " (master restored from the backup, nothing published)", restored=True, done=True)
        print("  FAILED at", failed, "-", reason)
    else:
        progress(jid, "live", "ok", f"LIVE v{job['to']}", done=True)
        print("  done, live", job["to"])
    try:
        call("helper.snapshot", text=master())
    except Exception as e:
        print("  snapshot failed:", e)


def main():
    print("WAOV installer helper: master", PS1)
    print("talking to", API)
    # On demand (Chad 2026-11-09): no all-day polling. Start it when you want to use the tile; it sends the master once,
    # watches for an approved plan every 20 s for 15 minutes, then closes itself. Each check is one Netlify function run.
    SESSION = 15 * 60
    end = time.time() + SESSION
    try:
        r = call("helper.snapshot", text=master())
        print(f"[{datetime.datetime.now():%H:%M:%S}] master v{r.get('version')} sent. Watching for an approved plan for 15 minutes.")
    except Exception as e:
        print("waov.art not reachable:", e)
    while time.time() < end:
        try:
            r = call("helper.next")
            if r.get("job"):
                run_job(r["job"])
                end = time.time() + SESSION          # stay open another 15 minutes after a job
        except Exception as e:
            print(f"[{datetime.datetime.now():%H:%M:%S}] waov.art not reachable: {e}")
        time.sleep(20)
    print("15 minutes are up: helper closed (no more Netlify calls). Start it again when you need the tile.")

if __name__ == "__main__":
    if "--once" in sys.argv:          # quick check: sign one snapshot and exit
        print(call("helper.snapshot", text=master()))
    else:
        main()

#!/usr/bin/env python3
"""
Migriert 'nur-Link'-Tasks aus Microsoft To Do nach Raindrop.

Regeln (von Dima):
  - Nur Tasks, deren Titel NUR ein Link ist.
  - Alter < 2026-01-01  -> Raindrop Archiv (58559702)
  - Alter >= 2026       -> Raindrop Unsorted (0)
  - Tag 'from-todo' an allen importierten Links.
  - Dubletten gegen bestehende Raindrops pruefen (nicht doppelt anlegen).
  - Nach erfolgreicher Anlage (bzw. bei Dublette) Task aus To Do loeschen.

Commands:
  build-index                Baut/aktualisiert den Raindrop-URL-Index.
  plan   [--limit N]         Zeigt, was passieren wuerde (kein Schreiben).
  run    [--limit N] --yes   Fuehrt Migration aus.

Quelle der To-Do-Tasks: neuestes backups/mstodo_backup_*.json
"""
import os, sys, re, json, time, glob, urllib.request, urllib.parse, urllib.error
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = HERE
while ROOT != "/" and not os.path.exists(os.path.join(ROOT, ".env")):
    ROOT = os.path.dirname(ROOT)
ENV_FILE = os.path.join(ROOT, ".env")
STATE_DIR = os.path.join(ROOT, ".agents", "skills", "microsoft-todo", "state")
os.makedirs(STATE_DIR, exist_ok=True)
INDEX_FILE = os.path.join(STATE_DIR, "raindrop_url_index.txt")
DONE_FILE  = os.path.join(STATE_DIR, "migrated_task_ids.txt")      # komplett fertig (aus To-Do geloescht)
RDDONE_FILE = os.path.join(STATE_DIR, "raindrop_done_task_ids.txt") # schon in Raindrop (nur noch loeschen)

ARCHIV_COL = 58559702
UNSORTED_COL = 0
TAG = "from-todo"
CUTOFF = "2026-01-01"

# ---------- .env ----------
def load_env():
    env = {}
    with open(ENV_FILE) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip().strip('"').strip("'")
    return env

def save_refresh(rt):
    lines = []
    found = False
    with open(ENV_FILE) as f:
        for line in f:
            if line.startswith("MSTODO_REFRESH_TOKEN="):
                lines.append(f"MSTODO_REFRESH_TOKEN={rt}\n"); found = True
            else:
                lines.append(line)
    if not found:
        lines.append(f"MSTODO_REFRESH_TOKEN={rt}\n")
    with open(ENV_FILE, "w") as f:
        f.writelines(lines)

ENV = load_env()
RAINDROP_TOKEN = ENV.get("RAINDROP_TOKEN") or ""
MS_CLIENT = ENV.get("MSTODO_CLIENT_ID") or ""
MS_REFRESH = ENV.get("MSTODO_REFRESH_TOKEN") or ""

# ---------- HTTP ----------
def http(method, url, headers=None, data=None, form=None, retries=6):
    headers = dict(headers or {})
    body = None
    if form is not None:
        body = urllib.parse.urlencode(form).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    elif data is not None:
        body = json.dumps(data).encode()
        headers["Content-Type"] = "application/json"
    for i in range(retries):
        req = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req) as r:
                raw = r.read().decode()
                return r.status, (json.loads(raw) if raw else {})
        except urllib.error.HTTPError as e:
            raw = e.read().decode()
            if e.code in (429, 500, 502, 503, 504):
                wait = int(e.headers.get("Retry-After", i + 1))
                time.sleep(wait); continue
            try: j = json.loads(raw)
            except Exception: j = {"raw": raw}
            return e.code, j
        except urllib.error.URLError:
            time.sleep(i + 1); continue
    return 0, {"error": "max retries"}

# ---------- Microsoft ----------
_access = {"tok": None}
def ms_token():
    global MS_REFRESH
    if _access["tok"]:
        return _access["tok"]
    st, j = http("POST", "https://login.microsoftonline.com/consumers/oauth2/v2.0/token",
                 form={"client_id": MS_CLIENT, "grant_type": "refresh_token",
                       "refresh_token": MS_REFRESH,
                       "scope": "Tasks.ReadWrite offline_access User.Read"})
    if "access_token" not in j:
        sys.exit(f"MS Token-Refresh fehlgeschlagen: {j.get('error_description', j)}")
    _access["tok"] = j["access_token"]
    if j.get("refresh_token"):
        MS_REFRESH = j["refresh_token"]; save_refresh(MS_REFRESH)
    return _access["tok"]

def ms_batch_delete(items):
    """items: list of (listId, taskId). Loescht robust in 20er-Batches mit Retry
    fuer gedrosselte (429) / fehlgeschlagene Sub-Requests. Gibt Set erfolgreicher taskIds."""
    ok = set()
    pending = list(items)
    attempt = 0
    while pending and attempt < 12:
        attempt += 1
        tok = ms_token()
        retry = []
        for i in range(0, len(pending), 20):
            chunk = pending[i:i+20]
            reqs = [{"id": str(n), "method": "DELETE",
                     "url": f"/me/todo/lists/{lid}/tasks/{tid}"}
                    for n, (lid, tid) in enumerate(chunk)]
            st, j = http("POST", "https://graph.microsoft.com/v1.0/$batch",
                         headers={"Authorization": f"Bearer {tok}"},
                         data={"requests": reqs})
            resps = {int(r["id"]): r for r in j.get("responses", [])}
            for n, (lid, tid) in enumerate(chunk):
                r = resps.get(n)
                code = r.get("status", 0) if r else 0
                if code in (204, 200, 404):   # 404 = schon weg -> ok
                    ok.add(tid)
                else:
                    retry.append((lid, tid))   # 429/5xx/andere -> nochmal
            time.sleep(0.6)
        if retry:
            print(f"    delete: {len(retry)} offen, Retry-Runde {attempt} (warte)", file=sys.stderr)
            time.sleep(3 * attempt)
        pending = retry
    return ok

# ---------- Raindrop ----------
def rd_headers():
    return {"Authorization": f"Bearer {RAINDROP_TOKEN}"}

def rd_all_collection_ids():
    ids = [0]
    for path in ("/collections", "/collections/childrens"):
        st, j = http("GET", f"https://api.raindrop.io/rest/v1{path}", headers=rd_headers())
        for c in j.get("items", []):
            ids.append(c["_id"])
    return ids

def rd_bulk_create(items, collection):
    """items: list of dicts {link, tags, [title]}. Legt bis 100 an. Gibt Anzahl erfolgreicher."""
    payload = []
    for it in items:
        d = {"link": it["link"], "collection": {"$id": collection},
             "tags": it["tags"], "pleaseParse": {}}
        if it.get("title"):
            d["title"] = it["title"]
        payload.append(d)
    st, j = http("POST", "https://api.raindrop.io/rest/v1/raindrops",
                 headers=rd_headers(), data={"items": payload})
    if j.get("result"):
        return len(j.get("items", []))
    return 0

# ---------- URL Normalisierung ----------
TRACK = {"s", "t", "utm_source", "utm_medium", "utm_campaign", "utm_term",
         "utm_content", "ref", "ref_src", "ref_url", "fbclid", "gclid",
         "igshid", "si", "feature", "app", "cxt"}
def norm_url(u):
    u = u.strip()
    if u.lower().startswith("www."):
        u = "https://" + u
    try:
        p = urllib.parse.urlsplit(u)
    except Exception:
        return u.lower()
    host = (p.hostname or "").lower()
    if host.startswith("www."): host = host[4:]
    if host in ("twitter.com", "mobile.twitter.com", "m.twitter.com"): host = "x.com"
    if host in ("m.youtube.com", "youtu.be"): host = "youtube.com"
    q = [(k, v) for k, v in urllib.parse.parse_qsl(p.query, keep_blank_values=True)
         if k.lower() not in TRACK]
    q.sort()
    path = p.path.rstrip("/")
    key = host + path
    if q:
        key += "?" + urllib.parse.urlencode(q)
    return key

# ---------- Index ----------
def rd_page(cid, page):
    """Holt eine Seite robust. Gibt (ok, items). ok=False => echter Fehler (retry sinnvoll)."""
    for attempt in range(8):
        st, j = http("GET",
            f"https://api.raindrop.io/rest/v1/raindrops/{cid}?perpage=50&page={page}",
            headers=rd_headers(), retries=8)
        if st == 200 and "items" in j:
            return True, j["items"]
        time.sleep(2 * (attempt + 1))   # 2,4,6,... s bei Fehler/429
    return False, []

def build_index():
    ids = list(dict.fromkeys(rd_all_collection_ids()))   # dedup ids
    seen = set(); total = 0
    with open(INDEX_FILE, "w") as f:
        for cid in ids:
            page = 0; cadd = 0
            while True:
                ok, items = rd_page(cid, page)
                if not ok:
                    print(f"  col {cid}: ABBRUCH bei page {page} (Fehler)", file=sys.stderr)
                    break
                if not items:
                    break
                for it in items:
                    link = it.get("link", "")
                    if not link: continue
                    k = norm_url(link)
                    if k not in seen:
                        seen.add(k); f.write(k + "\n"); total += 1; cadd += 1
                page += 1
                time.sleep(0.35)   # drosseln: ~<120 req/min
                if page > 2000: break
            print(f"  col {cid}: +{cadd} neu (gesamt {total})", file=sys.stderr)
            f.flush()
    print(f"Index gebaut: {total} eindeutige URLs -> {INDEX_FILE}", file=sys.stderr)

def load_index():
    if not os.path.exists(INDEX_FILE):
        sys.exit("Kein Index. Zuerst: build-index")
    with open(INDEX_FILE) as f:
        return set(l.strip() for l in f if l.strip())

def _load_set(path):
    if not os.path.exists(path): return set()
    with open(path) as f:
        return set(l.strip() for l in f if l.strip())

def _append(path, ids):
    with open(path, "a") as f:
        for t in ids: f.write(t + "\n")

def load_done():   return _load_set(DONE_FILE)
def load_rddone(): return _load_set(RDDONE_FILE)
def add_done(ids):   _append(DONE_FILE, ids)
def add_rddone(ids): _append(RDDONE_FILE, ids)

# ---------- Quelle ----------
URL_RE = re.compile(r"^\s*(https?://|www\.)\S+\s*$", re.I)
URL_FIND = re.compile(r"https?://\S+", re.I)

def load_note_link_tasks():
    """'Getarnte Bookmarks': Titel ist KEIN reiner Link, aber die Notiz enthaelt einen Link."""
    files = sorted(glob.glob(os.path.join(ROOT, "backups", "mstodo_backup_*.json")))
    if not files:
        sys.exit("Kein To-Do-Backup gefunden.")
    src = files[-1]
    with open(src) as f:
        data = json.load(f)
    out = []
    for lst in data["lists"]:
        for t in lst["tasks"]:
            title = t.get("title", "")
            if URL_RE.match(title):        # reine Link-Titel: anderer Modus
                continue
            note = (t.get("body") or {}).get("content", "") or ""
            m2 = URL_FIND.search(note)
            if not m2:
                continue
            url = m2.group(0).rstrip(").,;'\"")
            clean_title = title.split("\n")[0].strip()[:250] or None
            created = t.get("createdDateTime", "")
            out.append({
                "listId": lst["id"], "taskId": t["id"],
                "url": url, "title": clean_title, "created": created,
                "col": ARCHIV_COL if (created and created < CUTOFF) else UNSORTED_COL,
            })
    return src, out

def load_link_tasks():
    files = sorted(glob.glob(os.path.join(ROOT, "backups", "mstodo_backup_*.json")))
    if not files:
        sys.exit("Kein To-Do-Backup gefunden.")
    src = files[-1]
    with open(src) as f:
        data = json.load(f)
    out = []
    for lst in data["lists"]:
        for t in lst["tasks"]:
            title = t.get("title", "")
            if not URL_RE.match(title):
                continue
            created = t.get("createdDateTime", "")
            out.append({
                "listId": lst["id"], "taskId": t["id"],
                "url": title.strip(), "created": created,
                "col": ARCHIV_COL if (created and created < CUTOFF) else UNSORTED_COL,
            })
    return src, out

# ---------- Plan / Run ----------
def build_worklist(limit, source=load_link_tasks):
    src, tasks = source()
    index = load_index()
    done = load_done()
    rddone = load_rddone()
    work = []
    for t in tasks:
        if t["taskId"] in done:
            continue
        # Schon in Raindrop? Dann nicht neu anlegen, nur noch loeschen.
        t["in_rd"] = t["taskId"] in rddone
        t["dup"] = t["in_rd"] or (norm_url(t["url"]) in index)
        work.append(t)
    if limit:
        work = work[:limit]
    return src, work

def summarize(src, work):
    dup = sum(1 for w in work if w["dup"])
    new = len(work) - dup
    arch = sum(1 for w in work if not w["dup"] and w["col"] == ARCHIV_COL)
    uns  = sum(1 for w in work if not w["dup"] and w["col"] == UNSORTED_COL)
    print(f"Quelle: {os.path.basename(src)}")
    print(f"Zu verarbeiten: {len(work)}")
    print(f"  Dubletten (nur To-Do-Delete):     {dup}")
    print(f"  NEU -> Archiv (58559702):         {arch}")
    print(f"  NEU -> Unsorted (0):              {uns}")
    print(f"  (alle NEU bekommen Tag '{TAG}')")
    print("Beispiele:")
    for w in work[:8]:
        tgt = "DUP" if w["dup"] else ("Archiv" if w["col"] == ARCHIV_COL else "Unsorted")
        print(f"  [{tgt:8}] {w['url'][:72]}")

def run(work):
    # 1) Neue nach Collection gruppieren und bulk anlegen (nur was noch nicht in Raindrop)
    created_ok_tasks = []   # taskIds erfolgreich neu in raindrop
    for col in (ARCHIV_COL, UNSORTED_COL):
        batch = [w for w in work if not w["dup"] and w["col"] == col]
        for i in range(0, len(batch), 100):
            chunk = batch[i:i+100]
            items = [{"link": w["url"], "tags": [TAG], "title": w.get("title")} for w in chunk]
            n = rd_bulk_create(items, col)
            if n >= 1:
                ids = [w["taskId"] for w in chunk]
                created_ok_tasks.extend(ids)
                add_rddone(ids)   # sofort persistieren: sind jetzt in Raindrop
                print(f"  Raindrop col {col}: {n}/{len(chunk)} angelegt", file=sys.stderr)
            else:
                print(f"  WARN: Anlage fehlgeschlagen (col {col}, {len(chunk)} Stk) -> To-Do bleibt", file=sys.stderr)
            time.sleep(0.5)
    # 2) Dubletten / schon-in-Raindrop: direkt zum Loeschen freigeben
    dup_tasks = [w["taskId"] for w in work if w["dup"]]
    add_rddone([w["taskId"] for w in work if w["dup"] and not w["in_rd"]])
    # 3) To-Do loeschen (nur verifizierte: neu angelegt ODER dup/schon-in-rd)
    ok_rd = set(created_ok_tasks) | set(dup_tasks)
    del_map = [(w["listId"], w["taskId"]) for w in work if w["taskId"] in ok_rd]
    ok = ms_batch_delete(del_map)
    add_done(list(ok))
    print(f"Fertig: {len(created_ok_tasks)} neu in Raindrop, "
          f"{len(dup_tasks)-sum(1 for w in work if w['in_rd'])} echte Dubletten, "
          f"{sum(1 for w in work if w['in_rd'])} bereits-in-RD, "
          f"{len(ok)}/{len(del_map)} aus To-Do geloescht.", file=sys.stderr)

def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    cmd = args[0]
    limit = None
    if "--limit" in args:
        limit = int(args[args.index("--limit") + 1])
    if cmd == "build-index":
        build_index()
    elif cmd == "plan":
        src, work = build_worklist(limit)
        summarize(src, work)
    elif cmd == "run":
        if "--yes" not in args:
            sys.exit("Sicherheit: 'run' braucht --yes")
        src, work = build_worklist(limit)
        summarize(src, work)
        run(work)
    elif cmd == "plan-notes":
        src, work = build_worklist(limit, source=load_note_link_tasks)
        summarize(src, work)
    elif cmd == "run-notes":
        if "--yes" not in args:
            sys.exit("Sicherheit: 'run-notes' braucht --yes")
        src, work = build_worklist(limit, source=load_note_link_tasks)
        summarize(src, work)
        run(work)
    else:
        sys.exit(__doc__)

if __name__ == "__main__":
    main()

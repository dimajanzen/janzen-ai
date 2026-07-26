#!/usr/bin/env python3
"""Paperless-ngx CLI wrapper (stdlib only).

Reads PAPERLESS_URL and PAPERLESS_TOKEN from the environment or from
`<skill>/.env`. Prints JSON to stdout. Never prints the token.
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import ssl
import sys
import time
import urllib.parse
import urllib.request
import uuid
from pathlib import Path
from typing import Any

# Force UTF-8 on stdout/stderr so em-dashes and umlauts survive on Windows
# (default cp1252 breaks piping to jq / other python).
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

SKILL_DIR = Path(__file__).resolve().parent.parent
ENV_FILE = SKILL_DIR / ".env"


# ---------- env / config ----------

def load_env() -> None:
    if not ENV_FILE.exists():
        return
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def cfg() -> tuple[str, str, bool]:
    url = os.environ.get("PAPERLESS_URL", "").rstrip("/")
    token = os.environ.get("PAPERLESS_TOKEN", "")
    verify = os.environ.get("PAPERLESS_VERIFY_SSL", "true").lower() != "false"
    if not url or not token:
        die("PAPERLESS_URL and PAPERLESS_TOKEN must be set (env or skill/.env)")
    return url, token, verify


def die(msg: str, code: int = 2) -> None:
    # Mask any accidental token leakage.
    tok = os.environ.get("PAPERLESS_TOKEN", "")
    if tok:
        msg = msg.replace(tok, "***")
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


# ---------- HTTP ----------

def _opener(verify: bool):
    ctx = ssl.create_default_context()
    if not verify:
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    return urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx))


def request(
    method: str,
    path: str,
    *,
    query: dict[str, Any] | None = None,
    json_body: Any = None,
    multipart: list[tuple[str, Any]] | None = None,
    raw_response: bool = False,
) -> Any:
    url, token, verify = cfg()
    full = url + path if path.startswith("/") else f"{url}/{path}"
    if query:
        q = {k: v for k, v in query.items() if v is not None}
        if q:
            full += ("&" if "?" in full else "?") + urllib.parse.urlencode(q, doseq=True)

    headers = {
        "Authorization": f"Token {token}",
        "Accept": "application/json",
        # Cloudflare in front of Paperless blocks Python-urllib's default UA.
        "User-Agent": os.environ.get(
            "PAPERLESS_USER_AGENT",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        ),
    }
    data: bytes | None = None

    if multipart is not None:
        boundary = f"----paperless{uuid.uuid4().hex}"
        headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
        data = _encode_multipart(multipart, boundary)
    elif json_body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(json_body).encode("utf-8")

    req = urllib.request.Request(full, data=data, method=method, headers=headers)
    try:
        with _opener(verify).open(req) as resp:
            payload = resp.read()
            if raw_response:
                return payload, dict(resp.headers)
            if not payload:
                return None
            ctype = resp.headers.get("Content-Type", "")
            if "application/json" in ctype:
                return json.loads(payload)
            return payload.decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        die(f"HTTP {e.code} {method} {path}: {body[:500]}")
    except urllib.error.URLError as e:
        die(f"connection failed: {e.reason}")


def _encode_multipart(fields: list[tuple[str, Any]], boundary: str) -> bytes:
    buf: list[bytes] = []
    for name, value in fields:
        buf.append(f"--{boundary}\r\n".encode())
        if isinstance(value, tuple):  # (filename, bytes, content_type)
            filename, content, ctype = value
            buf.append(
                f'Content-Disposition: form-data; name="{name}"; filename="{filename}"\r\n'
                f"Content-Type: {ctype}\r\n\r\n".encode()
            )
            buf.append(content)
            buf.append(b"\r\n")
        else:
            buf.append(
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
            )
    buf.append(f"--{boundary}--\r\n".encode())
    return b"".join(buf)


def paginate(path: str, query: dict[str, Any] | None = None) -> list[dict]:
    results: list[dict] = []
    page = request("GET", path, query=query)
    while page:
        results.extend(page.get("results", []))
        nxt = page.get("next")
        if not nxt:
            break
        # Strip base URL to reuse request()
        base, _, tail = nxt.partition("/api/")
        page = request("GET", "/api/" + tail)
    return results


def out(obj: Any, *, fields: list[str] | None = None) -> None:
    if fields and isinstance(obj, dict):
        obj = {k: obj.get(k) for k in fields}
    if isinstance(obj, (dict, list)):
        json.dump(obj, sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
    elif obj is None:
        print("null")
    else:
        print(obj)


def summarize_doc(d: dict) -> str:
    return (
        f"#{d['id']} | {d.get('title','')}\n"
        f"  date={d.get('created_date')} type={d.get('document_type')} "
        f"corr={d.get('correspondent')} tags={d.get('tags')}"
    )


# ---------- helpers ----------

def parse_id_list(s: str | None) -> list[int] | None:
    if s is None:
        return None
    return [int(x) for x in s.split(",") if x.strip()]


def find_one(endpoint: str, name: str) -> dict | None:
    res = request("GET", endpoint, query={"name__iexact": name})
    hits = res.get("results", [])
    return hits[0] if hits else None


# ---------- commands ----------

def cmd_ping(_a):
    out(request("GET", "/api/ui_settings/"))


def cmd_stats(_a):
    out(request("GET", "/api/statistics/"))


def cmd_search(a):
    q = {"query": a.query, "page_size": a.limit}
    out(request("GET", "/api/documents/", query=q))


def cmd_list_docs(a):
    q: dict[str, Any] = {"page_size": a.limit, "ordering": a.ordering}
    if a.tag:
        q["tags__id__all"] = ",".join(str(t) for t in a.tag)
    if a.correspondent:
        q["correspondent__id"] = a.correspondent
    if a.type:
        q["document_type__id"] = a.type
    if a.created_after:
        q["created__date__gte"] = a.created_after
    if a.created_before:
        q["created__date__lte"] = a.created_before
    data = paginate("/api/documents/", q) if a.all else request("GET", "/api/documents/", query=q)
    if a.short:
        results = data if isinstance(data, list) else data.get("results", [])
        total = len(data) if isinstance(data, list) else data.get("count")
        print(f"{total} Dokument(e):")
        for d in results:
            print(summarize_doc(d))
    else:
        out(data)


def cmd_get_doc(a):
    out(request("GET", f"/api/documents/{a.id}/"))


def cmd_preview(a):
    doc = request("GET", f"/api/documents/{a.id}/")
    print(doc.get("content", ""))


def cmd_download(a):
    suffix = "/download/" + ("?original=true" if a.original else "")
    payload, headers = request("GET", f"/api/documents/{a.id}{suffix}", raw_response=True)
    path = Path(a.out) if a.out else Path(f"doc-{a.id}.pdf")
    path.write_bytes(payload)
    print(str(path.resolve()))


def cmd_update_doc(a):
    body: dict[str, Any] = {}
    if a.title is not None: body["title"] = a.title
    if a.correspondent is not None: body["correspondent"] = a.correspondent
    if a.doc_type is not None: body["document_type"] = a.doc_type
    if a.storage_path is not None: body["storage_path"] = a.storage_path
    if a.date is not None: body["created_date"] = a.date
    if a.asn is not None: body["archive_serial_number"] = a.asn

    tags = parse_id_list(a.tags)
    add = parse_id_list(a.add_tags) or []
    rem = set(parse_id_list(a.remove_tags) or [])
    if tags is not None:
        body["tags"] = tags
    elif add or rem:
        current = request("GET", f"/api/documents/{a.id}/")["tags"]
        merged = [t for t in current if t not in rem] + [t for t in add if t not in current]
        body["tags"] = merged

    if not body and not a.note:
        die("nothing to update")

    result = None
    if body:
        result = request("PATCH", f"/api/documents/{a.id}/", json_body=body)
    if a.note:
        request("POST", f"/api/documents/{a.id}/notes/", json_body={"note": a.note})
        if result is None:
            result = request("GET", f"/api/documents/{a.id}/")

    if a.short and isinstance(result, dict):
        print(summarize_doc(result))
    else:
        out(result)


def cmd_upload(a):
    p = Path(a.file)
    if not p.is_file():
        die(f"file not found: {p}")
    ctype = mimetypes.guess_type(p.name)[0] or "application/octet-stream"
    fields: list[tuple[str, Any]] = [("document", (p.name, p.read_bytes(), ctype))]
    if a.title: fields.append(("title", a.title))
    if a.correspondent is not None: fields.append(("correspondent", str(a.correspondent)))
    if a.doc_type is not None: fields.append(("document_type", str(a.doc_type)))
    if a.date: fields.append(("created", a.date))
    if a.asn is not None: fields.append(("archive_serial_number", str(a.asn)))
    for tid in parse_id_list(a.tags) or []:
        fields.append(("tags", str(tid)))
    task_uuid = request("POST", "/api/documents/post_document/", multipart=fields)
    print(task_uuid if isinstance(task_uuid, str) else json.dumps(task_uuid))


def cmd_task(a):
    tries = a.wait if a.wait else 1
    delay = 2
    last = None
    for _ in range(tries):
        res = request("GET", "/api/tasks/", query={"task_id": a.uuid})
        last = res[0] if isinstance(res, list) and res else res
        status = (last or {}).get("status") if isinstance(last, dict) else None
        if not a.wait or status in ("SUCCESS", "FAILURE"):
            break
        time.sleep(delay)
    out(last)


# --- metadata listings ---

def _list_meta(endpoint: str, name_contains: str | None, all_pages: bool):
    q = {"name__icontains": name_contains, "page_size": 100}
    return paginate(endpoint, q) if all_pages else request("GET", endpoint, query=q)


def cmd_list_tags(a): out(_list_meta("/api/tags/", a.name_contains, a.all))
def cmd_list_correspondents(a): out(_list_meta("/api/correspondents/", a.name_contains, a.all))
def cmd_list_doctypes(a): out(_list_meta("/api/document_types/", a.name_contains, a.all))
def cmd_list_storage_paths(a): out(_list_meta("/api/storage_paths/", a.name_contains, a.all))
def cmd_list_custom_fields(_a): out(request("GET", "/api/custom_fields/"))


def cmd_create_tag(a):
    body = {"name": a.name}
    if a.color: body["color"] = a.color
    out(request("POST", "/api/tags/", json_body=body))


def cmd_create_correspondent(a):
    out(request("POST", "/api/correspondents/", json_body={"name": a.name}))


def cmd_create_doctype(a):
    out(request("POST", "/api/document_types/", json_body={"name": a.name}))


_KIND_ENDPOINT = {
    "tag": "/api/tags/",
    "correspondent": "/api/correspondents/",
    "doctype": "/api/document_types/",
}


def cmd_resolve(a):
    endpoint = _KIND_ENDPOINT[a.kind]
    ids: list[int] = []
    for name in [n.strip() for n in a.names.split(",") if n.strip()]:
        hit = find_one(endpoint, name)
        if hit:
            ids.append(hit["id"])
        elif a.create:
            created = request("POST", endpoint, json_body={"name": name})
            ids.append(created["id"])
        else:
            die(f"{a.kind} not found: {name!r} (use --create to add)")
    # Print IDs comma-separated for shell use.
    print(",".join(str(i) for i in ids))


def cmd_raw(a):
    body = json.loads(a.json) if a.json else None
    if a.method == "DELETE" and not a.confirm_delete:
        die("DELETE requires --confirm-delete")
    if a.all and a.method == "GET":
        out(paginate(a.path))
    else:
        out(request(a.method, a.path, json_body=body))


# ---------- CLI ----------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="paperless.py", description="Paperless-ngx CLI")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("ping").set_defaults(fn=cmd_ping)
    sub.add_parser("stats").set_defaults(fn=cmd_stats)

    sp = sub.add_parser("search"); sp.add_argument("query"); sp.add_argument("--limit", type=int, default=25); sp.set_defaults(fn=cmd_search)

    sp = sub.add_parser("list-docs")
    sp.add_argument("--tag", type=int, action="append")
    sp.add_argument("--correspondent", type=int)
    sp.add_argument("--type", type=int)
    sp.add_argument("--created-after"); sp.add_argument("--created-before")
    sp.add_argument("--limit", type=int, default=25)
    sp.add_argument("--ordering", default="-created")
    sp.add_argument("--all", action="store_true")
    sp.add_argument("--short", action="store_true", help="one-line-per-doc summary instead of JSON")
    sp.set_defaults(fn=cmd_list_docs)

    sp = sub.add_parser("get-doc"); sp.add_argument("id", type=int); sp.set_defaults(fn=cmd_get_doc)
    sp = sub.add_parser("preview"); sp.add_argument("id", type=int); sp.set_defaults(fn=cmd_preview)

    sp = sub.add_parser("download"); sp.add_argument("id", type=int)
    sp.add_argument("--out"); sp.add_argument("--original", action="store_true")
    sp.set_defaults(fn=cmd_download)

    sp = sub.add_parser("update-doc"); sp.add_argument("id", type=int)
    sp.add_argument("--title"); sp.add_argument("--correspondent", type=int)
    sp.add_argument("--doc-type", type=int); sp.add_argument("--storage-path", type=int)
    sp.add_argument("--tags"); sp.add_argument("--add-tags"); sp.add_argument("--remove-tags")
    sp.add_argument("--date"); sp.add_argument("--asn", type=int); sp.add_argument("--note")
    sp.add_argument("--short", action="store_true", help="one-line summary instead of full JSON")
    sp.set_defaults(fn=cmd_update_doc)

    sp = sub.add_parser("upload"); sp.add_argument("file")
    sp.add_argument("--title"); sp.add_argument("--correspondent", type=int)
    sp.add_argument("--doc-type", type=int); sp.add_argument("--tags")
    sp.add_argument("--date"); sp.add_argument("--asn", type=int)
    sp.set_defaults(fn=cmd_upload)

    sp = sub.add_parser("task"); sp.add_argument("uuid")
    sp.add_argument("--wait", type=int, default=0, help="poll N times, 2s apart")
    sp.set_defaults(fn=cmd_task)

    for name, fn in [
        ("list-tags", cmd_list_tags),
        ("list-correspondents", cmd_list_correspondents),
        ("list-doctypes", cmd_list_doctypes),
        ("list-storage-paths", cmd_list_storage_paths),
    ]:
        sp = sub.add_parser(name)
        sp.add_argument("--name-contains")
        sp.add_argument("--all", action="store_true")
        sp.set_defaults(fn=fn)

    sub.add_parser("list-custom-fields").set_defaults(fn=cmd_list_custom_fields)

    sp = sub.add_parser("create-tag"); sp.add_argument("name"); sp.add_argument("--color"); sp.set_defaults(fn=cmd_create_tag)
    sp = sub.add_parser("create-correspondent"); sp.add_argument("name"); sp.set_defaults(fn=cmd_create_correspondent)
    sp = sub.add_parser("create-doctype"); sp.add_argument("name"); sp.set_defaults(fn=cmd_create_doctype)

    sp = sub.add_parser("resolve")
    sp.add_argument("kind", choices=["tag", "correspondent", "doctype"])
    sp.add_argument("names", help="comma-separated names")
    sp.add_argument("--create", action="store_true")
    sp.set_defaults(fn=cmd_resolve)

    sp = sub.add_parser("raw")
    sp.add_argument("method", choices=["GET", "POST", "PATCH", "PUT", "DELETE"])
    sp.add_argument("path")
    sp.add_argument("--json", help="JSON body string")
    sp.add_argument("--all", action="store_true", help="follow pagination (GET only)")
    sp.add_argument("--confirm-delete", action="store_true")
    sp.set_defaults(fn=cmd_raw)

    return p


def main() -> None:
    load_env()
    args = build_parser().parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()

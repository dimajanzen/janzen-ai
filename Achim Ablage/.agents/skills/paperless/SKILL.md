---
name: paperless
description: Interact with a Paperless-ngx document management instance via its REST API. Use when the user wants to search, view, upload (consume), tag, or update documents; manage correspondents, document types, tags, custom fields, storage paths; check tasks; or answer "where is the document from …?" questions for the Janzen family archive.
homepage: https://docs.paperless-ngx.com/api/
---

# Paperless-ngx

Thin wrapper around the Paperless-ngx REST API. All calls go through
`scripts/paperless.py` (Python, stdlib only) which reads credentials from the
environment.

## Configuration

Credentials live in `skills/paperless/.env` (git-ignored) OR the shell env:

```
PAPERLESS_URL=https://paperless.example.tld
PAPERLESS_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
# optional
PAPERLESS_VERIFY_SSL=true
```

The script auto-loads `.env` from the skill directory. Never print the token.

Get a token in Paperless UI → *My Profile* → *API Auth Token*.

## Quick reference

All commands are subcommands of `scripts/paperless.py`. Output is JSON on stdout.

| Command | Purpose |
|---|---|
| `ping` | Verify URL + token (calls `/api/ui_settings/`) |
| `search "<query>"` | Full-text search documents |
| `list-docs [--tag T] [--correspondent C] [--type T] [--created-after YYYY-MM-DD] [--limit N] [--short]` | Filtered document list (`--short` = one-line-per-doc summary) |
| `get-doc <id>` | Full document metadata |
| `download <id> [--out PATH] [--original]` | Download archived (or original) PDF |
| `preview <id>` | Print extracted OCR text (content field) |
| `update-doc <id> [--title ...] [--correspondent ID] [--doc-type ID] [--tags 1,2,3] [--add-tags 4] [--remove-tags 5] [--date YYYY-MM-DD] [--asn N] [--storage-path ID] [--note "..."] [--short]` | Patch metadata (`--short` prints compact summary) |
| `upload <file> [--title ...] [--correspondent ID] [--doc-type ID] [--tags 1,2] [--date YYYY-MM-DD] [--asn N]` | Send file to consumer, returns task UUID |
| `task <uuid>` | Poll consume task status |
| `list-tags [--name-contains X]` / `list-correspondents` / `list-doctypes` / `list-storage-paths` / `list-custom-fields` | List metadata objects |
| `create-tag <name> [--color #RRGGBB]` / `create-correspondent <name>` / `create-doctype <name>` | Create metadata objects |
| `resolve tag\|correspondent\|doctype <name>` | Return ID (create with `--create` if missing) |
| `stats` | Instance statistics |

Run `scripts/paperless.py --help` or `<cmd> --help` for full flags.

**Windows tip:** stdout is forced to UTF-8, so em-dashes (`—`) and umlauts
survive when piping. Prefer `--short` on `list-docs` / `update-doc` for
human-readable one-liners; use bare JSON output only when you actually need
to parse fields with `jq` or Python.

## Core workflows

### 1. Answer "where is …?" questions

```bash
scripts/paperless.py search "Stromrechnung 2024"
# then, for a hit:
scripts/paperless.py get-doc 1234
scripts/paperless.py download 1234 --out /tmp/doc.pdf
```

Prefer `search` (full-text) for content-based questions and `list-docs
--correspondent …` for "all documents from company X".

### 2. File a new document (upload + tag)

1. Resolve or create the correspondent and doctype (returns IDs):
   ```bash
   CID=$(scripts/paperless.py resolve correspondent "Stadtwerke München" --create)
   TID=$(scripts/paperless.py resolve doctype "Rechnung" --create)
   ```
2. Resolve tags (comma-separated IDs):
   ```bash
   TAGS=$(scripts/paperless.py resolve tag "Familie/Papa","Finanzen","2025" --create)
   ```
3. Upload — Paperless consumes asynchronously:
   ```bash
   TASK=$(scripts/paperless.py upload ./scan.pdf \
       --title "2025-01-14 — Stadtwerke München — Rechnung Januar" \
       --correspondent $CID --doc-type $TID --tags $TAGS \
       --date 2025-01-14)
   scripts/paperless.py task $TASK   # poll until SUCCESS, then get the new doc id
   ```

**Title convention (Janzen family):** `YYYY-MM-DD — Correspondent — Short description`.

### 3. Re-tag / correct metadata on an existing doc

```bash
scripts/paperless.py update-doc 1234 \
    --add-tags 7,12 --remove-tags 3 \
    --correspondent 42 --date 2024-11-30
```

Use `--add-tags` / `--remove-tags` rather than `--tags` unless a full replace
is intended.

### 4. Bulk / advanced queries

For anything the CLI does not expose directly, call the API through the
`raw` escape hatch:

```bash
scripts/paperless.py raw GET '/api/documents/?ordering=-created&page_size=5'
scripts/paperless.py raw PATCH /api/documents/1234/ --json '{"archive_serial_number": 42}'
```

The `raw` command handles auth, base URL, JSON encoding, and pagination
(`--all` flag follows `next` links).

## Guardrails

- **Never delete documents** without explicit user confirmation (`DELETE
  /api/documents/<id>/` is available via `raw` but requires an extra
  `--confirm-delete` flag).
- **Never log or echo the token.** The script masks it in error output.
- **Dates:** always ISO `YYYY-MM-DD`. Paperless field is `created_date`
  (document date), not `created` (upload timestamp).
- **Tags/correspondents by ID, not by name** in write calls — use `resolve`
  to convert.
- **Duplicates:** the consumer rejects exact-hash duplicates; on upload
  failure, check `task` output for `"DUPLICATE"`.

## References

- `references/api-endpoints.md` — endpoint cheat-sheet (documents, tags,
  correspondents, custom fields, tasks, bulk_edit, search filters).
- `references/janzen-conventions.md` — family-specific tags, correspondents
  naming, storage paths, per-person tag scheme.

Load a reference only when the current task actually needs it.

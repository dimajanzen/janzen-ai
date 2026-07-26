# Paperless-ngx API cheat-sheet

Base: `PAPERLESS_URL` — auth header: `Authorization: Token <PAPERLESS_TOKEN>`.
All list endpoints are paginated (`?page=N&page_size=…`, default 25, max 100000).

## Documents — `/api/documents/`

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/documents/` | List / filter |
| GET | `/api/documents/{id}/` | Retrieve (incl. OCR `content`) |
| PATCH | `/api/documents/{id}/` | Update metadata |
| DELETE | `/api/documents/{id}/` | Delete |
| GET | `/api/documents/{id}/download/` | Archived PDF (`?original=true` for source) |
| GET | `/api/documents/{id}/preview/` | Inline PDF |
| GET | `/api/documents/{id}/thumb/` | Thumbnail |
| GET | `/api/documents/{id}/metadata/` | File metadata (checksums, size) |
| GET/POST | `/api/documents/{id}/notes/` | List / add notes |
| POST | `/api/documents/post_document/` | **Upload** (multipart) → returns task UUID |
| POST | `/api/documents/bulk_edit/` | Bulk operations (see below) |

### Common filters for `GET /api/documents/`

- `query=<fulltext>` — full-text search
- `title__icontains=`, `content__icontains=`
- `correspondent__id=`, `document_type__id=`, `storage_path__id=`
- `tags__id__all=1,2` (all of), `tags__id__in=1,2` (any of), `is_tagged=true|false`
- `created__date__gte=YYYY-MM-DD`, `created__date__lte=…`
- `added__date__gte=…` (upload time), `modified__date__gte=…`
- `archive_serial_number=`, `archive_serial_number__isnull=true`
- `ordering=-created` / `created` / `-added` / `title`

### Writable fields (PATCH)

`title`, `correspondent` (id|null), `document_type` (id|null),
`storage_path` (id|null), `tags` (list of ids — replaces!),
`created_date` (YYYY-MM-DD, this is the **document date**),
`archive_serial_number` (int|null), `custom_fields` (list of
`{field: id, value: …}`).

### `POST /api/documents/post_document/` (multipart form-data)

Fields: `document` (file, required), `title`, `created` (YYYY-MM-DD),
`correspondent`, `document_type`, `archive_serial_number`, `tags`
(repeat field per tag id). Returns a task UUID (string).

Poll status via `/api/tasks/?task_id=<uuid>` → `status` in
`PENDING | STARTED | SUCCESS | FAILURE`. On success the response
contains `related_document` (the new document id).

### `POST /api/documents/bulk_edit/`

```json
{
  "documents": [1, 2, 3],
  "method": "add_tag" | "remove_tag" | "set_correspondent" |
            "set_document_type" | "set_storage_path" |
            "modify_tags" | "delete" | "redo_ocr" | "set_permissions",
  "parameters": { "tag": 5 }  // method-dependent
}
```

`modify_tags` params: `{"add_tags": [ids], "remove_tags": [ids]}`.

## Metadata objects

| Endpoint | Notes |
|---|---|
| `/api/tags/` | fields: `name`, `color` (`#RRGGBB`), `is_inbox_tag`, `matching_algorithm`, `match` |
| `/api/correspondents/` | `name`, matching fields |
| `/api/document_types/` | `name`, matching fields |
| `/api/storage_paths/` | `name`, `path` (template with `{correspondent}`, `{document_type}`, `{created_year}`, `{title}`) |
| `/api/custom_fields/` | `name`, `data_type` (`string`, `url`, `date`, `boolean`, `integer`, `float`, `monetary`, `documentlink`, `select`) |

All support `?name__iexact=` and `?name__icontains=` for lookup.

`matching_algorithm`: 0=None, 1=Any, 2=All, 3=Literal, 4=Regex, 5=Fuzzy, 6=Auto.

## Tasks — `/api/tasks/`

- `GET /api/tasks/` — recent tasks
- `GET /api/tasks/?task_id=<uuid>` — filter by task uuid
- `POST /api/tasks/acknowledge/` — dismiss failed tasks: `{"tasks":[id,...]}`

## Misc

- `/api/ui_settings/` — sanity check auth
- `/api/statistics/` — counts, inbox size
- `/api/search/autocomplete/?term=…&limit=10`
- `/api/logs/` — server logs (`mail`, `paperless`)
- `/api/config/` — runtime config (admin)

## Errors

- `400` — validation (body contains field-level errors)
- `401` — token missing / invalid
- `403` — permission denied (per-object permissions may apply)
- `404` — id / endpoint unknown
- Upload duplicates: task ends `FAILURE` with `result` containing
  `"It is a duplicate of ..."`.

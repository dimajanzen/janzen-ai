#!/usr/bin/env bash
# Raindrop.io CLI helper for Bob Brain
# Requires: curl, jq. Reads RAINDROP_TOKEN from env or nearest .env file.
set -euo pipefail

API="https://api.raindrop.io/rest/v1"

# --- Load token from .env if not already in env ---------------------------
load_token() {
  if [[ -n "${RAINDROP_TOKEN:-}" ]]; then return; fi
  local dir; dir="$(pwd)"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.env" ]]; then
      local v; v="$(grep -E '^RAINDROP_TOKEN=' "$dir/.env" | head -n1 | cut -d= -f2- | tr -d '"'"'"'' )"
      if [[ -n "$v" ]]; then export RAINDROP_TOKEN="$v"; return; fi
    fi
    dir="$(dirname "$dir")"
  done
  echo "ERROR: RAINDROP_TOKEN nicht gefunden (env oder .env)." >&2
  exit 1
}

req() {
  local method="$1" path="$2"; shift 2
  curl -sS -X "$method" "$API$path" \
    -H "Authorization: Bearer $RAINDROP_TOKEN" \
    -H "Content-Type: application/json" "$@"
}

usage() {
  cat >&2 <<'EOF'
Usage: raindrop.sh <command> [args]

  -- Lesen / Suchen --
  collections                     Alle Collections (mit Baum/Parent)
  tree                            Collections als Hierarchie
  list [collectionId] [perpage]   Bookmarks auflisten (0=Unsorted, -1=alle)
  get <id>                        Volle Details eines Bookmarks (inkl. excerpt, note, highlights)
  search "<query>" [collectionId] Volltext-/Tag-Suche (#tag)
  inbox [n]                       Ungesichtete Inbox-Items (ohne Status-Tag) für Review, mit excerpt
  stats                           Übersicht: Anzahl je Collection

  -- Erfassen / Ändern --
  add "<url>" ["title"] ["tag1,tag2"] [collectionId]
  update <id> <title|tags|collection|note|excerpt|important> "<value>"
  move <id> <collectionId>        Bookmark verschieben
  tag-add <id> "tag1,tag2"        Tags ergänzen (ohne bestehende zu überschreiben)
  tag-remove <id> "tag1,tag2"     Einzelne Tags entfernen
  status <id> <inbox|to-explore|reference>   Workflow-Status setzen (ersetzt andere Status-Tags)
  delete <id>                     Bookmark löschen

  -- Batch / Aufräumen --
  batch-move <collectionId> "id1,id2,..."     Mehrere verschieben
  create-collection "<title>" [parentId]      Neue Collection (optional als Unterordner)
  tags [collectionId]             Tags auflisten (mit Count)
  tag-rename "<alt>" "<neu>"       Tag umbenennen/zusammenführen (global)
  tag-drop "<tag1,tag2>"           Tag(s) global löschen
EOF
  exit 1
}

# Helper: comma-list -> JSON array (trimmt Whitespace)
csv_to_json() { printf '%s' "$1" | jq -R 'split(",") | map(gsub("^ +| +$";"")) | map(select(length>0))'; }

STATUS_TAGS='["inbox","to-explore","reference"]'

load_token
cmd="${1:-}"; shift || true

case "$cmd" in
  collections)
    roots="$(req GET "/collections" | jq '[.items[] | {id: ._id, title, count, parent: null}]')"
    kids="$(req GET "/collections/childrens" | jq '[.items[] | {id: ._id, title, count, parent: (.parent["$id"])} | select(.parent != null)]')"
    jq -n --argjson r "$roots" --argjson k "$kids" '($r + $k) | unique_by(.id)[]'
    ;;
  tree)
    roots="$(req GET "/collections" | jq '[.items[] | {id: ._id, title, count}]')"
    kids="$(req GET "/collections/childrens" | jq '[.items[] | {id: ._id, title, count, parent: (.parent["$id"])} | select(.parent != null)]')"
    jq -rn --argjson r "$roots" --argjson k "$kids" '
      $r[] | . as $root | "\($root.title) (\($root.count)) [id \($root.id)]",
      ( $k[] | select(.parent==$root.id) | "  └─ \(.title) (\(.count)) [id \(.id)]" )
    '
    ;;
  list)
    col="${1:-0}"; per="${2:-50}"
    req GET "/raindrops/$col?perpage=$per" | jq '.items[] | {id: ._id, title, link, tags}'
    ;;
  get)
    id="${1:?id fehlt}"
    req GET "/raindrop/$id" | jq '.item | {id: ._id, title, link, excerpt, note, tags, important, collection: .collection["$id"], highlights: [.highlights[]?.text]}'
    ;;
  search)
    q="${1:?query fehlt}"; col="${2:-0}"
    req GET "/raindrops/$col" --get --data-urlencode "search=$q" \
      | jq '.items[] | {id: ._id, title, link, tags}'
    ;;
  inbox)
    n="${1:-20}"
    # Items in Unsorted (0) ohne Status-Tag → ungesichtet
    req GET "/raindrops/0?perpage=$n&sort=-created" \
      | jq --argjson st "$STATUS_TAGS" '.items[]
          | select([.tags[] as $t | $st | index($t)] | all(.==null))
          | {id: ._id, title, link, excerpt, tags}'
    ;;
  stats)
    req GET "/collections" | jq -r '.items[] | "\(.count)\t\(.title)"' | sort -rn
    ;;
  add)
    url="${1:?url fehlt}"; title="${2:-}"; tags="${3:-}"; col="${4:-0}"
    tagsjson="[]"; [[ -n "$tags" ]] && tagsjson="$(csv_to_json "$tags")"
    body="$(jq -n --arg link "$url" --arg title "$title" \
      --argjson tags "$tagsjson" --argjson col "$col" \
      '{link:$link, collection:{"$id":$col}, tags:$tags}
       + (if $title=="" then {} else {title:$title} end)
       + {pleaseParse:{}}')"
    req POST "/raindrop" -d "$body" | jq '.item | {id: ._id, title, link, tags}'
    ;;
  update)
    id="${1:?id fehlt}"; field="${2:?feld fehlt}"; value="${3:?wert fehlt}"
    case "$field" in
      title)      body="$(jq -n --arg v "$value" '{title:$v}')" ;;
      note)       body="$(jq -n --arg v "$value" '{note:$v}')" ;;
      excerpt)    body="$(jq -n --arg v "$value" '{excerpt:$v}')" ;;
      important)  body="$(jq -n --argjson v "$value" '{important:$v}')" ;;
      tags)       body="$(csv_to_json "$value" | jq '{tags: .}')" ;;
      collection) body="$(jq -n --argjson v "$value" '{collection:{"$id":$v}}')" ;;
      *) echo "Unbekanntes Feld: $field" >&2; exit 1 ;;
    esac
    req PUT "/raindrop/$id" -d "$body" | jq '.item | {id: ._id, title, link, tags, collection: .collection["$id"]}'
    ;;
  move)
    id="${1:?id fehlt}"; col="${2:?collectionId fehlt}"
    req PUT "/raindrop/$id" -d "$(jq -n --argjson v "$col" '{collection:{"$id":$v}}')" \
      | jq '.item | {id: ._id, title, collection: .collection["$id"]}'
    ;;
  tag-add)
    id="${1:?id fehlt}"; new="${2:?tags fehlen}"
    cur="$(req GET "/raindrop/$id" | jq '.item.tags')"
    merged="$(jq -n --argjson a "$cur" --argjson b "$(csv_to_json "$new")" '($a+$b)|unique')"
    req PUT "/raindrop/$id" -d "$(jq -n --argjson t "$merged" '{tags:$t}')" | jq '.item | {id: ._id, tags}'
    ;;
  tag-remove)
    id="${1:?id fehlt}"; rem="${2:?tags fehlen}"
    cur="$(req GET "/raindrop/$id" | jq '.item.tags')"
    kept="$(jq -n --argjson a "$cur" --argjson b "$(csv_to_json "$rem")" '$a - $b')"
    req PUT "/raindrop/$id" -d "$(jq -n --argjson t "$kept" '{tags:$t}')" | jq '.item | {id: ._id, tags}'
    ;;
  status)
    id="${1:?id fehlt}"; st="${2:?status fehlt}"
    case "$st" in inbox|to-explore|reference) ;; *) echo "Status: inbox|to-explore|reference" >&2; exit 1 ;; esac
    cur="$(req GET "/raindrop/$id" | jq '.item.tags')"
    new="$(jq -n --argjson a "$cur" --argjson st "$STATUS_TAGS" --arg s "$st" '($a - $st) + [$s] | unique')"
    req PUT "/raindrop/$id" -d "$(jq -n --argjson t "$new" '{tags:$t}')" | jq '.item | {id: ._id, tags}'
    ;;
  batch-move)
    col="${1:?collectionId fehlt}"; ids="${2:?ids fehlen}"
    idsjson="$(printf '%s' "$ids" | jq -R 'split(",")|map(gsub("^ +| +$";"")|tonumber)')"
    req PUT "/raindrops/0" -d "$(jq -n --argjson ids "$idsjson" --argjson v "$col" '{ids:$ids, collection:{"$id":$v}}')" | jq '{modified: .modified}'
    ;;
  create-collection)
    title="${1:?titel fehlt}"; parent="${2:-}"
    if [[ -n "$parent" ]]; then
      body="$(jq -n --arg t "$title" --argjson p "$parent" '{title:$t, parent:{"$id":$p}}')"
    else
      body="$(jq -n --arg t "$title" '{title:$t}')"
    fi
    req POST "/collection" -d "$body" | jq '.item | {id: ._id, title, parent: (.parent["$id"] // null)}'
    ;;
  tags)
    col="${1:-}"
    req GET "/tags${col:+/$col}" | jq '.items | sort_by(-.count)[] | {tag: ._id, count}'
    ;;
  tag-rename)
    old="${1:?alt fehlt}"; new="${2:?neu fehlt}"
    req PUT "/tags" -d "$(jq -n --arg o "$old" --arg n "$new" '{tags:[$o], replace:$n}')" | jq '{result}'
    ;;
  tag-drop)
    tags="${1:?tags fehlen}"
    req DELETE "/tags" -d "$(jq -n --argjson t "$(csv_to_json "$tags")" '{tags:$t}')" | jq '{result}'
    ;;
  delete)
    id="${1:?id fehlt}"
    req DELETE "/raindrop/$id" | jq '{result}'
    ;;
  *)
    usage
    ;;
esac

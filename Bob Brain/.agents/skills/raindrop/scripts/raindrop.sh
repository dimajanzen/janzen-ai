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
  collections
  list [collectionId]
  search "<query>" [collectionId]
  add "<url>" ["title"] ["tag1,tag2"] [collectionId]
  update <id> <title|tags|collection> "<value>"
  delete <id>
  tags
EOF
  exit 1
}

load_token
cmd="${1:-}"; shift || true

case "$cmd" in
  collections)
    req GET "/collections" | jq '.items[] | {id: ._id, title, count}'
    ;;
  list)
    col="${1:-0}"
    req GET "/raindrops/$col?perpage=50" | jq '.items[] | {id: ._id, title, link, tags}'
    ;;
  search)
    q="${1:?query fehlt}"; col="${2:-0}"
    req GET "/raindrops/$col" --get --data-urlencode "search=$q" \
      | jq '.items[] | {id: ._id, title, link, tags}'
    ;;
  add)
    url="${1:?url fehlt}"; title="${2:-}"; tags="${3:-}"; col="${4:-0}"
    tagsjson="[]"
    if [[ -n "$tags" ]]; then
      tagsjson="$(printf '%s' "$tags" | jq -R 'split(",") | map(gsub("^ +| +$";""))')"
    fi
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
      tags)       body="$(printf '%s' "$value" | jq -R '{tags: (split(",") | map(gsub("^ +| +$";"")))}')" ;;
      collection) body="$(jq -n --argjson v "$value" '{collection:{"$id":$v}}')" ;;
      *) echo "Unbekanntes Feld: $field (title|tags|collection)" >&2; exit 1 ;;
    esac
    req PUT "/raindrop/$id" -d "$body" | jq '.item | {id: ._id, title, link, tags}'
    ;;
  delete)
    id="${1:?id fehlt}"
    req DELETE "/raindrop/$id" | jq '{result}'
    ;;
  tags)
    req GET "/tags" | jq '.items[] | {tag: ._id, count}'
    ;;
  *)
    usage
    ;;
esac

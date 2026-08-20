#!/usr/bin/env bash
set -euo pipefail

# Microsoft To Do CLI via Microsoft Graph API (persönliches Konto)
# Auth: OAuth2 Device Code Flow + Refresh Token (in .env)

# ── .env laden (aus Projektroot suchen) ──────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
find_env() {
  local dir="$SCRIPT_DIR"
  while [ "$dir" != "/" ]; do
    [ -f "$dir/.env" ] && { echo "$dir/.env"; return; }
    dir="$(dirname "$dir")"
  done
}
ENV_FILE="$(find_env || true)"
[ -n "${ENV_FILE:-}" ] && [ -f "$ENV_FILE" ] && set -a && . "$ENV_FILE" && set +a

TENANT="consumers"   # persönliche @live/@outlook Konten
AUTH="https://login.microsoftonline.com/$TENANT/oauth2/v2.0"
GRAPH="https://graph.microsoft.com/v1.0"
SCOPE="Tasks.ReadWrite offline_access User.Read"

: "${MSTODO_CLIENT_ID:?MSTODO_CLIENT_ID fehlt in .env}"

err() { echo "Fehler: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || err "'$1' wird benötigt"; }
need curl; need jq

# ── Refresh-Token in .env schreiben/aktualisieren ────────────
save_refresh() {
  local rt="$1"
  [ -z "$rt" ] && return
  if grep -q '^MSTODO_REFRESH_TOKEN=' "$ENV_FILE"; then
    # inplace ersetzen (portabel)
    local tmp; tmp="$(mktemp)"
    awk -v v="$rt" '/^MSTODO_REFRESH_TOKEN=/{print "MSTODO_REFRESH_TOKEN="v; next} {print}' "$ENV_FILE" > "$tmp"
    mv "$tmp" "$ENV_FILE"
  else
    echo "MSTODO_REFRESH_TOKEN=$rt" >> "$ENV_FILE"
  fi
}

# ── Access-Token holen (via Refresh-Token) ───────────────────
ACCESS_TOKEN=""
get_access_token() {
  [ -n "${MSTODO_REFRESH_TOKEN:-}" ] || err "Nicht eingeloggt. Zuerst: mstodo.sh login"
  local resp
  resp="$(curl -s -X POST "$AUTH/token" \
    -d "client_id=$MSTODO_CLIENT_ID" \
    -d "grant_type=refresh_token" \
    -d "refresh_token=$MSTODO_REFRESH_TOKEN" \
    --data-urlencode "scope=$SCOPE")"
  local at rt errc
  at="$(echo "$resp" | jq -r '.access_token // empty')"
  rt="$(echo "$resp" | jq -r '.refresh_token // empty')"
  if [ -z "$at" ]; then
    errc="$(echo "$resp" | jq -r '.error_description // .error // "unbekannt"')"
    err "Token-Refresh fehlgeschlagen: $errc. Ggf. neu einloggen (login)."
  fi
  ACCESS_TOKEN="$at"
  [ -n "$rt" ] && { save_refresh "$rt"; MSTODO_REFRESH_TOKEN="$rt"; }
}

api() {
  local method="$1" path="$2" body="${3:-}"
  [ -n "$ACCESS_TOKEN" ] || get_access_token
  local url="$path"
  [[ "$path" == http* ]] || url="$GRAPH$path"
  if [ -n "$body" ]; then
    curl -s -X "$method" "$url" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$body"
  else
    curl -s -X "$method" "$url" \
      -H "Authorization: Bearer $ACCESS_TOKEN"
  fi
}

# ── LOGIN: Device Code Flow ──────────────────────────────────
cmd_login() {
  echo "→ Starte Microsoft-Login (Device Code)..." >&2
  local dc
  dc="$(curl -s -X POST "$AUTH/devicecode" \
    -d "client_id=$MSTODO_CLIENT_ID" \
    --data-urlencode "scope=$SCOPE")"
  local device_code user_code verify interval
  device_code="$(echo "$dc" | jq -r '.device_code // empty')"
  user_code="$(echo "$dc" | jq -r '.user_code // empty')"
  verify="$(echo "$dc" | jq -r '.verification_uri // empty')"
  interval="$(echo "$dc" | jq -r '.interval // 5')"
  [ -z "$device_code" ] && err "Device-Code fehlgeschlagen: $(echo "$dc" | jq -r '.error_description // .')"

  echo "" >&2
  echo "════════════════════════════════════════════" >&2
  echo "  1) Öffne:  $verify" >&2
  echo "  2) Code:   $user_code" >&2
  echo "  3) Mit deinem @live-Konto anmelden & bestätigen" >&2
  echo "════════════════════════════════════════════" >&2
  echo "Warte auf Bestätigung..." >&2

  while true; do
    sleep "$interval"
    local resp at rt errc
    resp="$(curl -s -X POST "$AUTH/token" \
      -d "client_id=$MSTODO_CLIENT_ID" \
      -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
      -d "device_code=$device_code")"
    at="$(echo "$resp" | jq -r '.access_token // empty')"
    if [ -n "$at" ]; then
      rt="$(echo "$resp" | jq -r '.refresh_token // empty')"
      save_refresh "$rt"
      echo "✅ Login erfolgreich. Refresh-Token in .env gespeichert." >&2
      return 0
    fi
    errc="$(echo "$resp" | jq -r '.error // empty')"
    case "$errc" in
      authorization_pending) : ;;                 # weiter warten
      slow_down) interval=$((interval+5)) ;;
      ""|null) : ;;
      *) err "Login fehlgeschlagen: $(echo "$resp" | jq -r '.error_description // .error')" ;;
    esac
  done
}

# ── Helpers: Listen-ID per Name/ID auflösen ──────────────────
resolve_list() {
  local q="$1"
  # Direkt-ID? (Graph-IDs sind lang mit == / AAA...)
  if [[ "$q" =~ ^AA ]] || [[ ${#q} -gt 60 ]]; then echo "$q"; return; fi
  api GET "/me/todo/lists?\$top=100" \
    | jq -r --arg n "$q" '.value[] | select((.displayName|ascii_downcase)==($n|ascii_downcase)) | .id' | head -1
}

# ── Commands ─────────────────────────────────────────────────
cmd_lists() {
  api GET "/me/todo/lists?\$top=100" \
    | jq -r '.value[] | "\(.id)\t\(.displayName)\(if .isOwner==false then " (geteilt)" else "" end)"' \
    | awk -F'\t' 'BEGIN{print "LISTEN:"} {printf "  • %s\n    id: %s\n", $2, $1}'
}

cmd_tasks() {
  local list="$1" filter="${2:-open}"
  local lid; lid="$(resolve_list "$list")"
  [ -z "$lid" ] && err "Liste nicht gefunden: $list"
  local q="/me/todo/lists/$lid/tasks?\$top=100&\$orderby=createdDateTime desc"
  case "$filter" in
    open)  q="$q&\$filter=status ne 'completed'" ;;
    done)  q="$q&\$filter=status eq 'completed'" ;;
    all)   : ;;
  esac
  api GET "$q" | jq -r '
    .value[] |
    "\(if .status=="completed" then "[x]" else "[ ]" end) \(.title)" +
    (if .dueDateTime then "  📅 " + (.dueDateTime.dateTime|split("T")[0]) else "" end) +
    (if .importance=="high" then "  ⭐" else "" end) +
    "\n    id: \(.id)" +
    (if (.body.content // "") != "" then "\n    📝 " + (.body.content|gsub("\n";" ")) else "" end)'
}

cmd_add() {
  local list="$1" title="$2" due="${3:-}" note="${4:-}" imp="${5:-}"
  local lid; lid="$(resolve_list "$list")"
  [ -z "$lid" ] && err "Liste nicht gefunden: $list"
  local body; body="$(jq -n --arg t "$title" '{title:$t}')"
  if [ -n "$due" ]; then
    body="$(echo "$body" | jq --arg d "$due" '.dueDateTime={dateTime:($d+"T00:00:00.000000"),timeZone:"UTC"}')"
  fi
  [ -n "$note" ] && body="$(echo "$body" | jq --arg n "$note" '.body={content:$n,contentType:"text"}')"
  [ -n "$imp" ] && body="$(echo "$body" | jq --arg i "$imp" '.importance=$i')"
  api POST "/me/todo/lists/$lid/tasks" "$body" \
    | jq -r 'if .id then "✅ Angelegt: \(.title)\n   id: \(.id)" else "Fehler: \(.error.message // .)" end'
}

cmd_done() {
  local list="$1" tid="$2"
  local lid; lid="$(resolve_list "$list")"
  api PATCH "/me/todo/lists/$lid/tasks/$tid" '{"status":"completed"}' \
    | jq -r 'if .id then "✅ Erledigt: \(.title)" else "Fehler: \(.error.message // .)" end'
}

cmd_reopen() {
  local list="$1" tid="$2"
  local lid; lid="$(resolve_list "$list")"
  api PATCH "/me/todo/lists/$lid/tasks/$tid" '{"status":"notStarted"}' \
    | jq -r 'if .id then "↩︎ Wieder offen: \(.title)" else "Fehler: \(.error.message // .)" end'
}

cmd_update() {
  local list="$1" tid="$2" field="$3" value="$4"
  local lid; lid="$(resolve_list "$list")"
  local body
  case "$field" in
    title)      body="$(jq -n --arg v "$value" '{title:$v}')" ;;
    note)       body="$(jq -n --arg v "$value" '{body:{content:$v,contentType:"text"}}')" ;;
    due)        body="$(jq -n --arg v "$value" '{dueDateTime:{dateTime:($v+"T00:00:00.000000"),timeZone:"UTC"}}')" ;;
    importance) body="$(jq -n --arg v "$value" '{importance:$v}')" ;;
    *) err "Feld unbekannt: $field (title|note|due|importance)" ;;
  esac
  api PATCH "/me/todo/lists/$lid/tasks/$tid" "$body" \
    | jq -r 'if .id then "✏️ Aktualisiert: \(.title)" else "Fehler: \(.error.message // .)" end'
}

cmd_delete() {
  local list="$1" tid="$2"
  local lid; lid="$(resolve_list "$list")"
  api DELETE "/me/todo/lists/$lid/tasks/$tid" >/dev/null
  echo "🗑 Gelöscht: $tid"
}

cmd_backup() {
  local dest="${1:-backups}"
  mkdir -p "$dest"
  local stamp; stamp="$(date +%Y-%m-%d_%H%M%S)"
  local out="$dest/mstodo_backup_$stamp.json"
  echo "→ Sichere alle Listen & Aufgaben..." >&2
  local lists; lists="$(api GET "/me/todo/lists?\$top=100")"
  local n_lists; n_lists="$(echo "$lists" | jq '.value | length')"
  echo "  $n_lists Listen gefunden" >&2
  # Für jede Liste alle Tasks (paginiert) holen
  echo '{' > "$out"
  echo "  \"backupDate\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"," >> "$out"
  echo '  "lists": [' >> "$out"
  local first=1 total=0
  local tmpd; tmpd="$(mktemp -d)"
  while IFS=$'\t' read -r lid lname; do
    [ -z "$lid" ] && continue
    : > "$tmpd/pages.jsonl"
    local url="/me/todo/lists/$lid/tasks?\$top=100"
    while [ -n "$url" ]; do
      local page; page="$(api GET "$url")"
      echo "$page" | jq -c '.value[]?' >> "$tmpd/pages.jsonl"
      url="$(echo "$page" | jq -r '."@odata.nextLink" // empty')"
    done
    local cnt; cnt="$(wc -l < "$tmpd/pages.jsonl" | tr -d ' ')"
    total=$((total+cnt))
    printf '  %s tasks in %s\n' "$cnt" "$lname" >&2
    [ $first -eq 0 ] && echo ',' >> "$out"
    first=0
    jq -s --arg id "$lid" --arg name "$lname" \
      '{id:$id, displayName:$name, taskCount:length, tasks:.}' "$tmpd/pages.jsonl" >> "$out"
  done < <(echo "$lists" | jq -r '.value[] | "\(.id)\t\(.displayName)"')
  rm -rf "$tmpd"
  echo '' >> "$out"
  echo '  ]' >> "$out"
  echo '}' >> "$out"
  echo "✅ Backup gespeichert: $out ($n_lists Listen, $total Aufgaben)" >&2
  echo "$out"
}

cmd_create_list() {
  api POST "/me/todo/lists" "$(jq -n --arg n "$1" '{displayName:$n}')" \
    | jq -r 'if .id then "✅ Liste angelegt: \(.displayName)\n   id: \(.id)" else "Fehler: \(.error.message // .)" end'
}

usage() {
  cat >&2 <<EOF
Microsoft To Do — Befehle:
  login                                  Einmaliger Login (Device Code)
  lists                                  Alle Aufgabenlisten
  tasks <liste> [open|done|all]          Aufgaben einer Liste (default: open)
  add <liste> "Titel" [YYYY-MM-DD] [note] [high]
  done <liste> <taskId>                  Aufgabe abhaken
  reopen <liste> <taskId>                Wieder öffnen
  update <liste> <taskId> <title|note|due|importance> "wert"
  delete <liste> <taskId>
  create-list "Name"                     Neue Liste
  backup [ordner]                        Vollständiges Backup (JSON, default: backups/)

<liste> = Name (z.B. "Aufgaben") ODER Listen-ID.
EOF
  exit 1
}

cmd="${1:-}"; shift || true
case "$cmd" in
  login)        cmd_login ;;
  lists)        cmd_lists ;;
  tasks)        cmd_tasks "$@" ;;
  add)          cmd_add "$@" ;;
  done)         cmd_done "$@" ;;
  reopen)       cmd_reopen "$@" ;;
  update)       cmd_update "$@" ;;
  delete)       cmd_delete "$@" ;;
  create-list)  cmd_create_list "$@" ;;
  backup)       cmd_backup "$@" ;;
  *) usage ;;
esac

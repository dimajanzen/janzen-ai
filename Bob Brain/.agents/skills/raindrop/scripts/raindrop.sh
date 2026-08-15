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

# Robuster GET mit Retry/Backoff bei Rate-Limit oder ungültigem JSON.
# Gibt gültiges JSON auf stdout, sonst leer + Rueckgabecode 1.
req_retry() {
  local path="$1" tries="${2:-6}" i=0 resp
  while [[ $i -lt $tries ]]; do
    resp="$(curl -sS "$API$path" -H "Authorization: Bearer $RAINDROP_TOKEN" -H "Content-Type: application/json" 2>/dev/null || true)"
    if printf '%s' "$resp" | jq -e '.items' >/dev/null 2>&1; then
      printf '%s' "$resp"; return 0
    fi
    i=$((i+1))
    sleep $((i))   # linearer Backoff: 1s,2s,3s ...
  done
  return 1
}

usage() {
  cat >&2 <<'EOF'
Usage: raindrop.sh <command> [args]

  -- Lesen / Suchen --
  collections                     Alle Collections (mit Baum/Parent)
  tree                            Collections als Hierarchie
  collection <id>                 Infos zu EINER Collection (Titel, Count)
  list [collectionId] [n] [sort]  Bookmarks (0=Unsorted, -1=alle; sort z.B. -created, created, -sort)
  get <id>                        Volle Details eines Bookmarks (inkl. excerpt, note, highlights)
  search "<query>" [collectionId] Volltext-/Tag-Suche (#tag)
  inbox [n]                       Ungesichtete Inbox-Items (ohne Status-Tag) für Review, mit excerpt
  stats                           Übersicht: Anzahl je Collection (inkl. Unsorted)
  move-before <srcCol> <dstCol> <YYYY-MM-DD>  Alle vor Datum verschieben (Amnestie)
  broken [collectionId]           Tote/broken Links finden
  duplicates [collectionId]       Doppelte URLs finden
  backup [zielordner]             Vollständiges Backup (Collections + alle Bookmarks) als JSON

  -- Erfassen / Ändern --
  add "<url>" ["title"] ["tag1,tag2"] [collectionId]
  update <id> <title|tags|collection|note|excerpt|important> "<value>"
  move <id> <collectionId>        Bookmark verschieben
  tag-add <id> "tag1,tag2"        Tags ergänzen (ohne bestehende zu überschreiben)
  tag-remove <id> "tag1,tag2"     Einzelne Tags entfernen
  status <id> <inbox|to-explore|reference>   Workflow-Status setzen (ersetzt andere Status-Tags)
  delete <id>                     Bookmark löschen

  -- Batch / Aufräumen --
  batch-move <srcCol> <dstCol> "id1,id2,..."  Mehrere verschieben (Quelle->Ziel)
  move-all <srcCol> <dstCol>                   GANZE Collection verschieben
  create-collection "<title>" [parentId]      Neue Collection (optional als Unterordner)
  rename-collection <id> "<title>"             Collection umbenennen
  delete-collection <id>                       Leere Collection loeschen
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

  collection)
    id="${1:?id fehlt}"
    req GET "/collection/$id" | jq '.item | {id: ._id, title, count, parent: (.parent["$id"] // null)}'
    ;;
  list)
    col="${1:-0}"; per="${2:-50}"; sort="${3:-}"
    req GET "/raindrops/$col?perpage=$per${sort:+&sort=$sort}" | jq '.items[] | {id: ._id, title, link, tags, created}'
    ;;
  broken)
    col="${1:--1}"; page=0; found=0
    while :; do
      resp="$(req GET "/raindrops/$col?perpage=50&page=$page")"
      cnt="$(echo "$resp" | jq '.items | length')"
      [[ "$cnt" -eq 0 ]] && break
      echo "$resp" | jq -c '.items[] | select(.broken==true) | {id: ._id, title, link}'
      found=$((found + $(echo "$resp" | jq '[.items[]|select(.broken==true)]|length')))
      page=$((page+1))
    done
    echo "# broken gesamt: $found" >&2
    ;;
  duplicates)
    col="${1:--1}"; page=0; tmp="$(mktemp)"
    while :; do
      resp="$(req GET "/raindrops/$col?perpage=50&page=$page")"
      cnt="$(echo "$resp" | jq '.items | length')"
      [[ "$cnt" -eq 0 ]] && break
      echo "$resp" | jq -r '.items[] | "\(.link)\t\(._id)\t\(.title)"' >> "$tmp"
      page=$((page+1))
    done
    # Gruppen mit gleicher URL (>1)
    awk -F'\t' '{c[$1]++; ids[$1]=ids[$1]","$2; t[$1]=$3} END{for(u in c) if(c[u]>1) printf "%d\t%s\t%s\n", c[u], u, ids[u]}' "$tmp" | sort -rn
    dupes="$(awk -F'\t' '{c[$1]++} END{n=0; for(u in c) if(c[u]>1) n++; print n}' "$tmp")"
    total="$(wc -l < "$tmp")"
    echo "# $total URLs gesamt, $dupes doppelte URL-Gruppen" >&2
    rm -f "$tmp"
    ;;
  backup)
    dir="${1:-backups}"; mkdir -p "$dir"
    ts="$(date +%Y%m%d-%H%M%S)"
    out="$dir/raindrop-backup-$ts.json"
    echo "# Backup läuft → $out" >&2
    cols="$(req GET "/collections" | jq '.items')"
    kids="$(req GET "/collections/childrens" | jq '.items')"
    page=0; itemsfile="$(mktemp)"; echo "[]" > "$itemsfile"
    total=0
    # Pro Collection ueber MEHRERE Sortierungen sammeln + per _id dedupen.
    # Grund: bei gleichen created-Timestamps ueberspringt eine einzelne Sortierung
    # an Seitengrenzen Eintraege. Die Union mehrerer Sortierungen faengt alle.
    SORTS=("-created" "-sort" "title" "domain")
    allcols="0 $(jq -n --argjson r "$cols" --argjson k "$kids" '($r + $k) | map(._id) | unique | .[]')"  # 0 = Unsorted mitsichern
    for col in $allcols; do
      before="$(jq 'length' "$itemsfile")"
      for s in "${SORTS[@]}"; do
        page=0
        while :; do
          if ! resp="$(req_retry "/raindrops/$col?perpage=50&page=$page&sort=$s")"; then
            echo "#   WARN: Collection $col sort $s Seite $page fehlgeschlagen – uebersprungen" >&2
            break
          fi
          cnt="$(printf '%s' "$resp" | jq '.items | length')"
          [[ "$cnt" -eq 0 ]] && break
          jq -s '(.[0] + .[1].items) | unique_by(._id)' "$itemsfile" <(printf '%s' "$resp") > "$itemsfile.tmp" && mv "$itemsfile.tmp" "$itemsfile"
          page=$((page+1))
        done
      done
      after="$(jq 'length' "$itemsfile")"
      echo "#   Collection $col: +$((after-before)) (unique gesamt $after)" >&2
    done
    total="$(jq 'length' "$itemsfile")"
    jq -n --argjson cols "$cols" --argjson kids "$kids" \
      --slurpfile items "$itemsfile" --arg ts "$ts" \
      '{exported_at:$ts, collections:$cols, child_collections:$kids, raindrops:$items[0], count:($items[0]|length)}' > "$out"
    rm -f "$itemsfile"
    echo "# Fertig: $total Bookmarks gesichert in $out" >&2
    echo "$out"
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
    uns="$(req GET "/raindrops/0?perpage=1" | jq '.count')"
    { echo -e "${uns}\t(0) Unsorted"; req GET "/collections" | jq -r '.items[] | "\(.count)\t\(.title)"'; } | sort -rn
    ;;
  move-before)
    src="${1:?srcCol fehlt}"; dst="${2:?dstCol fehlt}"; date="${3:?datum YYYY-MM-DD fehlt}"; moved=0
    while :; do
      resp="$(req_retry "/raindrops/$src?perpage=50&sort=created")" || break
      ids="$(printf '%s' "$resp" | jq --arg d "$date" '[.items[] | select(.created < $d) | ._id]')"
      cnt="$(printf '%s' "$ids" | jq 'length')"
      [[ "$cnt" -eq 0 ]] && break
      req PUT "/raindrops/$src" -d "$(jq -n --argjson ids "$ids" --argjson v "$dst" '{ids:$ids, collection:{"$id":$v}}')" >/dev/null
      moved=$((moved+cnt)); echo "#   verschoben (vor $date): $moved" >&2; sleep 1
    done
    echo "{\"moved\": $moved}"
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
    src="${1:?srcCol fehlt}"; dst="${2:?dstCol fehlt}"; ids="${3:?ids fehlen}"
    idsjson="$(printf '%s' "$ids" | jq -R 'split(",")|map(gsub("^ +| +$";"")|tonumber)')"
    req PUT "/raindrops/$src" -d "$(jq -n --argjson ids "$idsjson" --argjson v "$dst" '{ids:$ids, collection:{"$id":$v}}')" | jq '{modified: .modified}'
    ;;
  move-all)
    src="${1:?srcCol fehlt}"; dst="${2:?dstCol fehlt}"; moved=0
    while :; do
      resp="$(req_retry "/raindrops/$src?perpage=50")" || break
      ids="$(printf '%s' "$resp" | jq '[.items[]._id]')"
      cnt="$(printf '%s' "$ids" | jq 'length')"
      [[ "$cnt" -eq 0 ]] && break
      req PUT "/raindrops/$src" -d "$(jq -n --argjson ids "$ids" --argjson v "$dst" '{ids:$ids, collection:{"$id":$v}}')" >/dev/null
      moved=$((moved+cnt)); echo "#   verschoben: $moved" >&2; sleep 1
    done
    echo "{\"moved\": $moved}"
    ;;
  rename-collection)
    id="${1:?id fehlt}"; title="${2:?titel fehlt}"
    req PUT "/collection/$id" -d "$(jq -n --arg t "$title" '{title:$t}')" | jq '.item | {id: ._id, title}'
    ;;
  delete-collection)
    id="${1:?id fehlt}"
    req DELETE "/collection/$id" | jq '{result}'
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

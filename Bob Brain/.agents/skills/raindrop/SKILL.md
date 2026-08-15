---
name: raindrop
description: Verwaltet Raindrop.io Bookmarks und Collections über die Raindrop REST API. Nutze diesen Skill, um Lesezeichen zu suchen, hinzuzufügen, zu aktualisieren, zu löschen, Collections aufzulisten und Links zu taggen. Ideal für Recherche, Wissensmanagement und das Ablegen von Links.
metadata:
  owner: Dima Janzen
  managed-by: Bob Brain
---

# Raindrop.io

Bookmark-Management über die [Raindrop REST API v1](https://developer.raindrop.io/).

## Setup

Der API-Token wird über die `.env` bereitgestellt. Der Skill liest automatisch
`RAINDROP_TOKEN` (Test-Token aus den App-Einstellungen von Raindrop).

```bash
# .env im Projektroot
RAINDROP_TOKEN=dein_test_token_hier
```

Token holen: https://app.raindrop.io/settings/integrations → "Create new app" → "Test token".

Voraussetzungen: `curl` und `jq`.

## Usage

Alle Aktionen laufen über ein Script:

```bash
./scripts/raindrop.sh <command> [args...]
```

### Lesen / Suchen
```bash
./scripts/raindrop.sh collections               # alle Collections (mit Parent)
./scripts/raindrop.sh tree                       # Collections als Hierarchie
./scripts/raindrop.sh stats                      # Anzahl Links je Collection
./scripts/raindrop.sh list [collectionId] [n]    # Bookmarks (0=Unsorted, -1=alle)
./scripts/raindrop.sh get <id>                   # volle Details: excerpt, note, tags, highlights
./scripts/raindrop.sh search "begriff" [colId]   # Volltext-/Tag-Suche (#tag)
./scripts/raindrop.sh inbox [n]                  # ungesichtete Inbox-Items (ohne Status-Tag) + excerpt
```

### Erfassen / Ändern
```bash
./scripts/raindrop.sh add "https://example.com" "Titel" "tag1,tag2" <colId>
./scripts/raindrop.sh update <id> <title|tags|collection|note|excerpt|important> "wert"
./scripts/raindrop.sh move <id> <collectionId>              # verschieben
./scripts/raindrop.sh tag-add <id> "tag1,tag2"             # Tags ergänzen (bestehende bleiben)
./scripts/raindrop.sh tag-remove <id> "tag1"               # einzelne Tags entfernen
./scripts/raindrop.sh status <id> <inbox|to-explore|reference>   # Workflow-Status setzen
./scripts/raindrop.sh delete <id>
```

### Batch / Aufräumen
```bash
./scripts/raindrop.sh batch-move <colId> "id1,id2,id3"     # mehrere verschieben
./scripts/raindrop.sh create-collection "Titel" [parentId] # neue (Unter-)Collection
./scripts/raindrop.sh tags [collectionId]                  # Tags mit Count
./scripts/raindrop.sh tag-rename "alt" "neu"               # Tag umbenennen/zusammenführen (global)
./scripts/raindrop.sh tag-drop "tag1,tag2"                 # Tag(s) global löschen
```

## Workflow-Konzept (Bob Brain)
**Collections = Bereiche** (ein Link lebt in genau einem), **Tags = Themen** (querschnittlich).
Status-Tags für die Sichtung: nur `inbox` (default/ungesichtet), `to-explore`, `reference`.

Weekly-Review-Loop:
1. `inbox 20` → ungesichtete Items mit excerpt ziehen
2. Pro Item bewerten: löschen / `status ... reference` / `status ... to-explore` / Info extrahieren
3. `move`/`batch-move` in die passende Bereichs-Collection

## Hinweise
- `collectionId` `0` = Unsorted, `-1` = alle, `-99` = Trash.
- Ausgaben sind JSON (via `jq` formatiert), gut zum Weiterverarbeiten.
- Bei Rate-Limits (429) kurz warten und erneut versuchen.

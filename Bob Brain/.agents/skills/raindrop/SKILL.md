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

### Collections auflisten
```bash
./scripts/raindrop.sh collections
```

### Bookmarks suchen / auflisten
```bash
./scripts/raindrop.sh list                      # alle (Collection 0 = Unsorted)
./scripts/raindrop.sh list <collectionId>       # in bestimmter Collection
./scripts/raindrop.sh search "suchbegriff"      # Volltextsuche
./scripts/raindrop.sh search "#tag begriff"     # nach Tag + Text
```

### Bookmark hinzufügen
```bash
./scripts/raindrop.sh add "https://example.com"
./scripts/raindrop.sh add "https://example.com" "Titel" "tag1,tag2" <collectionId>
```

### Bookmark aktualisieren
```bash
./scripts/raindrop.sh update <raindropId> title "Neuer Titel"
./scripts/raindrop.sh update <raindropId> tags "tag1,tag2"
./scripts/raindrop.sh update <raindropId> collection <collectionId>
```

### Bookmark löschen
```bash
./scripts/raindrop.sh delete <raindropId>
```

### Tags auflisten
```bash
./scripts/raindrop.sh tags
```

## Hinweise
- `collectionId` `0` = Unsorted, `-1` = alle, `-99` = Trash.
- Ausgaben sind JSON (via `jq` formatiert), gut zum Weiterverarbeiten.
- Bei Rate-Limits (429) kurz warten und erneut versuchen.

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
./scripts/raindrop.sh collection <id>            # Infos zu EINER Collection
./scripts/raindrop.sh stats                      # Anzahl Links je Collection
./scripts/raindrop.sh list [colId] [n] [sort]    # Bookmarks (sort: -created, created, -sort ...)
./scripts/raindrop.sh get <id>                   # volle Details: excerpt, note, tags, highlights
./scripts/raindrop.sh search "begriff" [colId]   # Volltext-/Tag-Suche (#tag)
./scripts/raindrop.sh inbox [n]                  # ungesichtete Inbox-Items (ohne Status-Tag) + excerpt
./scripts/raindrop.sh broken [colId]             # tote/broken Links finden
./scripts/raindrop.sh duplicates [colId]         # doppelte URLs finden
./scripts/raindrop.sh backup [zielordner]        # vollständiges Backup als JSON (default: backups/)
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
./scripts/raindrop.sh batch-move <srcCol> <dstCol> "id1,id2"  # mehrere verschieben
./scripts/raindrop.sh move-all <srcCol> <dstCol>           # ganze Collection verschieben
./scripts/raindrop.sh create-collection "Titel" [parentId] # neue (Unter-)Collection
./scripts/raindrop.sh rename-collection <id> "Titel"       # Collection umbenennen
./scripts/raindrop.sh delete-collection <id>              # leere Collection löschen
./scripts/raindrop.sh tags [collectionId]                  # Tags mit Count
./scripts/raindrop.sh tag-rename "alt" "neu"               # Tag umbenennen/zusammenführen (global)
./scripts/raindrop.sh tag-drop "tag1,tag2"                 # Tag(s) global löschen
```

## Workflow (Bob Brain × Dima)

**Grundprinzip:** Der **Ort** ist der Status. Ein Link gilt als gesichtet, wenn er **Unsorted verlässt**.
Unsorted (0) tendiert gegen 0. Collections = Bereiche, Tags = Themen.

```
Unsorted (Eingang) → Bob sortiert vor → Dima entscheidet → Link einsortiert / Archiv / ⭐ / weg
```

### Rollen
- **Dima = erfassen:** Speichert Links wie gewohnt (LinkedIn/Twitter/Browser/Mobile).
  Landet automatisch in **Unsorted**. Kein Taggen, kein Nachdenken nötig.
- **Bob = sichten/bewerten/aufbereiten:** Auf Zuruf ("mach einen Batch").
- **Dima = entscheiden:** Überfliegt Bobs Vorschläge, sagt "alle ok" oder korrigiert einzeln.

### Digest-Batch (so führt Bob es aus)
1. N neueste/älteste **echte** Unsorted-Items holen (Filter `collection.$id == -1`):
   `./scripts/raindrop.sh get <id>` bzw. Seite aus `/raindrops/0?sort=-created`.
2. Pro Link aufbereiten: **1–2-Satz-Zusammenfassung** (aus `title`+`excerpt`, ggf. Seite lesen) +
   **Vorschlag**: Bereich (Collection) + saubere Tags (aus dem 100er-Kernvokabular) + **Aktion**:
   - 🗑 löschen (`delete`) · 🗄 Archiv (`move ... 90`) · 📁 Bereich (`move ... <col>`) · ⭐ to-explore
3. Fehltags proaktiv korrigieren (falsch gesetzte Tags ersetzen).
4. Nach Dimas OK ausführen: `update <id> tags "..."` + `move <id> <col>` (oder `delete`).
5. Standard-Batchgröße: 20. Demo/klein: 5. Altbestand: größer + nur Zweifelsfälle vorlegen.

### ⭐ To-Explore
Die sichtbare Liste "das will ich wirklich angehen" (eigene Collection). Löst das alte Problem
"taggen und nie wieder anschauen". Reine Nachschlage-Links → Bereich/Archiv statt to-explore.

### Tag-Konvention
klein · englisch · Singular · Personen mit `@name` · Mehrwort `mit-bindestrich`.
Keine Status-Tags (Status = Ort). Vokabular/Referenz: `notes/raindrop-tags-vorschlag.md`.

### Merksatz
> Dima wirft rein. Bob sortiert vor. Dima entscheidet in Minuten. Unsorted geht auf 0.

## Hinweise
- `collectionId` `0` = Unsorted, `-1` = alle, `-99` = Trash.
- Ausgaben sind JSON (via `jq` formatiert), gut zum Weiterverarbeiten.
- Bei Rate-Limits (429) kurz warten und erneut versuchen.

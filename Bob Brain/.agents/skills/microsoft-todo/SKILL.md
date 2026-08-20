---
name: microsoft-todo
description: Verwaltet Microsoft To Do Aufgaben und Listen über die Microsoft Graph API (persönliches @live/@outlook-Konto). Nutze diesen Skill, um Aufgaben zu lesen, anzulegen, abzuhaken, zu ändern, Fälligkeiten zu setzen und Listen zu verwalten. Ideal für Task- und To-do-Management von Dima.
metadata:
  owner: Dima Janzen
  managed-by: Bob Brain
---

# Microsoft To Do

Task-Management über die [Microsoft Graph API](https://learn.microsoft.com/graph/api/resources/todo-overview) für Dimas persönliches **@live-Konto**.

## Setup

Config in `.env` (Projektroot):

```bash
MSTODO_CLIENT_ID=4c44980d-cc86-421f-abed-92fe41de6c93
MSTODO_REFRESH_TOKEN=          # wird beim login automatisch gefüllt
```

Voraussetzungen: `curl` und `jq`.

### Einmaliger Login (Device Code Flow)
```bash
./scripts/mstodo.sh login
```
Script zeigt eine URL + Code. Dima öffnet die URL, gibt den Code ein, meldet sich mit
dem @live-Konto an und bestätigt. Danach wird der **Refresh-Token** automatisch in `.env`
gespeichert — kein erneuter Login nötig (Token wird automatisch erneuert).

App-Registrierung (Azure/Entra): Personal accounts only, Delegated `Tasks.ReadWrite` +
`offline_access` + `User.Read`, Public client flows = Yes.

## Usage

```bash
./scripts/mstodo.sh <command> [args...]
```

### Lesen
```bash
./scripts/mstodo.sh lists                        # alle Listen (mit IDs)
./scripts/mstodo.sh tasks "Aufgaben"             # offene Aufgaben einer Liste
./scripts/mstodo.sh tasks "Aufgaben" done        # erledigte
./scripts/mstodo.sh tasks "Aufgaben" all         # alle
```

### Erfassen / Ändern
```bash
./scripts/mstodo.sh add "Aufgaben" "Titel"                       # simpel
./scripts/mstodo.sh add "Aufgaben" "Titel" 2026-01-15            # mit Fälligkeit
./scripts/mstodo.sh add "Aufgaben" "Titel" 2026-01-15 "Notiz" high  # + Notiz + wichtig
./scripts/mstodo.sh done "Aufgaben" <taskId>                     # abhaken
./scripts/mstodo.sh reopen "Aufgaben" <taskId>                   # wieder öffnen
./scripts/mstodo.sh update "Aufgaben" <taskId> title "Neuer Titel"
./scripts/mstodo.sh update "Aufgaben" <taskId> due 2026-02-01
./scripts/mstodo.sh update "Aufgaben" <taskId> note "Text"
./scripts/mstodo.sh update "Aufgaben" <taskId> importance high
./scripts/mstodo.sh delete "Aufgaben" <taskId>
```

### Listen verwalten
```bash
./scripts/mstodo.sh create-list "Neue Liste"
```

## Workflow (Bob × Dima) — so bleibt To Do sauber

**Grundprinzip (wie bei Raindrop):** Der **Ort** ist der Status. Dima wirft rein,
Bob sortiert vor, Dima entscheidet in Minuten. **"Aufgaben" = Eingang und tendiert gegen 0.**

### Die 3 eisernen Regeln
1. **Links gehören NICHT in To Do.** Ein reiner Link/Bookmark → immer nach Raindrop.
   Landet doch mal einer in To Do, holt Bob ihn raus (`migrate_todo_links.py run` / `run-notes`).
2. **"Aufgaben" ist die Inbox.** Dima wirft alles ungefiltert rein — kein Taggen, kein Nachdenken.
3. **Fertig = weg.** Abgehakte Tasks werden regelmäßig gelöscht (kein Completed-Friedhof).

### Rollen
- **Dima = erfassen:** Neue To-dos schnell in "Aufgaben" (oder "Mein Tag"). Fertig.
- **Bob = triagieren:** Auf Zuruf ("Bob, Inbox aufräumen") geht Bob die Inbox durch und schlägt pro Task vor:
  - 🔗 **Link** → nach Raindrop (Tag `from-todo`)
  - ✅ **echte Aufgabe** → richtige **Bereichsliste** (Company, Sales, Development, Me …) + optional 📅 Fälligkeit / ⭐ `importance high`
  - 🗄 **veraltet** → Liste "📦 Archiv"
  - 🗑 **Müll/Dublette** → löschen
- **Dima = entscheiden:** Überfliegt Bobs Vorschläge, sagt "alle ok" oder korrigiert einzeln.

### Rhythmus
- **Laufend:** Dima erfasst in "Aufgaben".
- **1× pro Woche (5 Min):** Bob-Triage der Inbox + erledigte löschen. → Inbox geht auf 0.
- **Bei Bedarf:** "die abgeschlossenen löschen" (Bob räumt Completed weg).

### Struktur
- **"Aufgaben"** = Inbox (leer halten)
- **Bereichslisten** = fertige Ablage nach Thema
- **"📦 Archiv"** = alt, aber aufgehoben (reversibel)

### Werkzeuge für die Triage
- Erledigte löschen (Loop bis 0): `scripts/../state/del_loop.py` bzw. Bob löscht per `$batch`.
- Titel entrümpeln (Link aus Titel → Notiz): `migrate_todo_links.py declutter-titles --yes`.
- Link-Tasks nach Raindrop: `migrate_todo_links.py run` (reine Links) / `run-notes` (Link in Notiz).

### Merksatz
> Dima wirft rein. Bob sortiert vor. Dima entscheidet in Minuten. Links nach Raindrop. Fertig = weg.

## Hinweise
- `<liste>` akzeptiert den **Namen** (z.B. "Aufgaben", "Tasks") oder die **Listen-ID**.
- Fälligkeiten im Format `YYYY-MM-DD` (wird als UTC gesetzt).
- Ausgaben sind menschenlesbar; Task-IDs stehen unter jedem Eintrag für Folgeaktionen.
- Bei Token-Problemen einfach erneut `login` ausführen.
- Die Standard-Liste heißt bei deutschen Konten meist **"Aufgaben"** (englisch: "Tasks").

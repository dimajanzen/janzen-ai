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

## Hinweise
- `<liste>` akzeptiert den **Namen** (z.B. "Aufgaben", "Tasks") oder die **Listen-ID**.
- Fälligkeiten im Format `YYYY-MM-DD` (wird als UTC gesetzt).
- Ausgaben sind menschenlesbar; Task-IDs stehen unter jedem Eintrag für Folgeaktionen.
- Bei Token-Problemen einfach erneut `login` ausführen.
- Die Standard-Liste heißt bei deutschen Konten meist **"Aufgaben"** (englisch: "Tasks").

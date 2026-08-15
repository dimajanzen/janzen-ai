# Raindrop-Überarbeitung – Plan & Durchführung

Stand: 2026-08-15 · Ausführung: Bob Brain (autonom) · Backup: in Git (5675 Bookmarks)

## Zielbild
Collections = Bereiche (ein Link = ein Ordner) · Tags = Themen · 3 Status-Tags im Workflow.

```
00 📥 Inbox                  (= bisherige "links", aktuell/arbeitend)
10 🏢 Cobby
   ├─ Product / PIM
   ├─ Marketing & GTM
   ├─ Sales
   └─ Tech / .NET
20 👥 Meine Kollegen
30 💡 Ideen & Startups
40 🧠 Learning / Second Brain
   ├─ AI & Dev
   ├─ Führung & Mindset
   └─ Bücher & Reading
50 🏡 Privat
90 🗄 Archiv                 (= bisherige "old_inbox", eingefroren)
```

## Ausführung (Phasen)
- P0 Backup ✅ (Git)
- P1 Struktur anlegen
- P2 old_inbox → "90 Archiv"; links → "00 Inbox"; links2_export → Archiv + löschen
- P3 Dubletten + broken Links → Papierkorb (recoverable)
- P4 Tag-Hygiene: Tippfehler/Merges + Status-Tags entfernen
- P5 Stark getaggte Inbox-Items in Bereiche routen; Rest bleibt Inbox (Weekly-Workflow)
- P6 Laufender Workflow: morgens erfassen → wöchentlicher Bob-Digest → Freitag entscheiden

## Vorgehen bei Änderungen
- Reversibel (bauen/umbenennen/umsortieren/taggen): direkt ausführen, danach Sichtungsliste.
- Löschen: geht in Raindrop-Papierkorb (wiederherstellbar) + Voll-Backup vorhanden.

## ERGEBNIS (2026-08-15, autonom ausgeführt)
- P1 ✅ Struktur angelegt (10 Cobby + 4 Unter, 20/30/50, 40 Learning + 3 Unter)
- P2 ✅ old_inbox → "90 Archiv"; links → "00 Inbox"; links2_export (152) → Archiv + gelöscht; leere "LinkedIn" gelöscht
- P3 ✅ 61 Dubletten (v.a. 33x/22x LinkedIn-Reimports) → Papierkorb; 0 tote Links
- P4 ✅ Tag-Hygiene: 383→373 Tags. Merges: markeing→marketing, .net+net→dotnet,
     mk beratung→mk, habbits→habits, enterpreneur→entrepreneur, architectur→architecture.
     Gedroppt (Status-Noise): urgent(749), tomorrow, today, todo, new-urgent, now, review.
- P5 ✅ 3 getaggte Inbox-Items geroutet; 842 untagged bleiben Arbeits-Inbox (Weekly-Digest).
- Backups: pre + post in Git (5675 → 5614 nach Dedupe).

### Endstand
```
00 Inbox (842) | 90 Archiv (4768) | Amy (1)
10 Cobby (+4 Unter) | 20 Meine Kollegen | 30 Ideen & Startups
40 Learning [AI & Dev (2), Fuehrung & Mindset (1), Buecher & Reading] | 50 Privat
```

## OFFEN / Nächster Schritt
- Weekly-Digest der 842 untagged Inbox-Links in 20er-Batches (Bob fasst zusammen +
  schlägt Collection/Tag/Status vor → Dima entscheidet). Auf Wunsch starten.
- Papierkorb (61) nach Sichtung endgültig leeren.

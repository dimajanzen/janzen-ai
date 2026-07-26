# Janzen — Ablage-Konventionen

Verbindliche Konventionen für Achim Ablage. Bei Unsicherheit: nachfragen,
nicht raten.

## Titel

`YYYY-MM-DD — Korrespondent — Kurzbeschreibung`

- Datum = **Dokumentdatum** (nicht Scan-/Upload-Datum) → Feld `created_date`.
- Korrespondent = offizieller Firmen-/Behördenname, kurz und konsistent
  (siehe Korrespondentenliste, Duplikate vermeiden).
- Kurzbeschreibung: was es ist + ggf. Zeitraum/Vertragsnr., z. B.
  `Rechnung Januar`, `Jahresabrechnung 2024`, `Vertrag Nr. 12345`.

## Familie Janzen

| Person | Rolle | Geburtsdatum | Tag | Tag-ID |
|---|---|---|---|---|
| Dietrich Janzen | IKK-Mitglied (KV-Nr. E878360612) | — | `person/dietrich` | 5 |
| Julia Janzen | Ehefrau, selbstständig | 16.08.1983 | `person/julia` | 6 |
| Jayden Janzen | Kind | 26.06.2013 | `person/jayden` | 7 |
| Justus Janzen | Kind | 23.01.2016 | `person/justus` | 8 |
| — | familien-übergreifend | — | `person/familie` | 9 |

Regel: jedes Dokument, das eine Person eindeutig betrifft, bekommt genau
ihren `person/<vorname>`-Tag zusätzlich zu den Sach-Tags. Dokumente, die
die ganze Familie betreffen (z. B. Familienversicherung, Miete), bekommen
`person/familie` — bei Bedarf zusätzlich die einzelnen Personen.

Wohnort: **Minden**, Sonnenkamp 5 A, 32427 Minden.

## Sach-Tags (Themen)

Kleinschreibung, hierarchisch mit `/`:

- `finanzen/rechnung`, `finanzen/mahnung`, `finanzen/kontoauszug`,
  `finanzen/steuern/<jahr>`
- `versicherung/<sparte>` — z. B. `versicherung/haftpflicht`,
  `versicherung/kfz`, `versicherung/kranken`
- `wohnen/miete`, `wohnen/strom`, `wohnen/gas`, `wohnen/wasser`,
  `wohnen/internet`, `wohnen/nebenkosten`
- `arbeit/<person>` — Lohn, Verträge, Bescheinigungen
- `behoerde/<amt>` — Finanzamt, Meldeamt, Familienkasse …
- `gesundheit/<person>` — Arztbriefe, Rezepte, Atteste
- `fahrzeug/<kennzeichen>` — alles zum jeweiligen Auto
- `bildung/<person>` — Schule, Uni, Zertifikate
- `vertrag/aktiv` vs. `vertrag/gekuendigt`

## Dokumenttypen (`document_type`)

Klein, generisch, sprach-neutral wo möglich: `Rechnung`, `Mahnung`,
`Vertrag`, `Kündigung`, `Bescheid`, `Bescheinigung`, `Kontoauszug`,
`Jahresabrechnung`, `Angebot`, `Lieferschein`, `Quittung`, `Antrag`,
`Arztbrief`, `Rezept`, `Zeugnis`, `Anschreiben`, `Sonstiges`.

## Storage Paths

Template: `{correspondent}/{created_year}/{document_type}/{title}`.
Nur setzen, wenn das Dokument sicher zugeordnet ist — sonst leer lassen
und Paperless in den Default-Pfad legen.

## Fristen & Inbox

- Neu konsumierte Dokumente tragen den Paperless-Standardtag `inbox`.
  Achim leert die Inbox: prüfen, taggen, Korrespondent + Doctype setzen,
  Datum korrigieren, dann `inbox` entfernen.
- Dokumente mit Frist (Zahlung, Widerspruch, Kündigung) bekommen
  zusätzlich `frist/<YYYY-MM-DD>` und werden in der Antwort an die
  Familie explizit erwähnt.
- Wichtige Verträge mit Kündigungsfrist: Tag `vertrag/aktiv` +
  `kuendigung-bis/<YYYY-MM-DD>` als Erinnerung.

## Duplikate

Vor Upload prüfen: `search "<absender> <datum> <betrag>"`. Beim
Consumer-Fehler `DUPLICATE` (Task-Status `FAILURE`) wird das existierende
Dokument nachgezogen und ggf. neu getaggt statt neu importiert.

## Was NICHT automatisch geschehen darf

- Löschen von Dokumenten
- Bulk-Delete oder Bulk-Retag über > 20 Dokumente
- Freigabe von Zahlungen, Vertragsabschlüssen, Kündigungen

Immer Rückfrage an die Familie.

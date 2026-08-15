# Raindrop Tags – Vorschlag & Bereinigung

Stand: 2026-08-15 · durchgeführt von Bob Brain

## Ausgangslage
373 Tags, sehr langer Schwanz: 258 Tags <10x, 118 nur 1x. Tippfehler, DE/EN-Mix,
inkonsistente Groß-/Kleinschreibung, alles flach vermischt (Tech/Thema/Person/Typ).

## Stufe A — Merges (erledigt ✅)
skills+skil→skill · tool→tools · ui+ux→ui/ux · habit+gewohnheiten→habits · ki→ai ·
Video→video · Voice→voice · Memory→memory · youtuber+YouTube→youtube ·
meinekollegen+mienekollegen+"mk marketing"+"mi marketing"+"mk use case"→mk ·
cobb→cobby · prompt→prompts · fitnes→fitness · zeitmanagment→zeitmanagement ·
peojects→project · plabook→playbook
=> 373 → 355

## Stufe B — Müll gelöscht (erledigt ✅)
blub t da pu li mn noe mal mi mol qs conte mark MPV Core Herdr ser pal rev lib log loop spin urge
=> 355 → 331

## Stufe C — Kern-Vokabular & Konvention (teilweise erledigt ✅)
Regel: immer klein, englisch, Singular-Nomen. Status = Ort (nicht Tag).

### Umgesetzt
- **Personen mit `@`-Präfix:** @dima @karpathy @adam @merath @dan @ralph @eve @alex @enzo @levelsio @ravi
- **Mehrwort-Tags mit Bindestrich:** ai-first, cold-calling, personal-brand, cold-email,
  ai-act, founder-led, lead-magnet, sales-navigator
- (`sei`, `clay` bewusst nicht als Person behandelt – mehrdeutig bzw. Tool)

### Konvention (going forward)
- Personen: `@name` · Mehrwort: `mit-bindestrich` · sonst: klein, englisch, Singular
- Status = Ort (Unsorted → To-Explore → Bereich → Archiv), keine Status-Tags mehr

### Kern-Vokabular (Referenz)
- 🤖 Tech/Tools: ai agents llm claude codex cursor mcp rag n8n dotnet react docker api prompts memory obsidian crawling
- 📈 GTM/Sales/Mktg: sales marketing seo gtm content outbound cold-calling crm icp pricing abm
- 🛒 Product/E-Com: pim ecommerce magento shopware
- 🧠 Learning/Mindset: books reading führung mindset habits productivity
- 💰 Privat/Finanzen: aktien trading finance health
- 👤 Personen: karpathy merath adam … (optional Präfix @)
- 📎 Content-Typ: video podcast newsletter playbook casestudy tool
- Optional: Facetten-Präfixe t/ f/ @  (selbst-gruppierend)

## Hinweis
Merges/Deletes wirken global (inkl. Archiv). Reversibel via Backup + tag-rename/re-add.

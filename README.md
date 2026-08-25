# tendercare-teacher

Staff dashboard for Tendercare Comprehensive College — broadsheets, score
entry, and the **single source of truth for the student roster**.

One of three independently-deployable apps in the Tendercare Svelte
migration:

| App | Repo | Role |
|---|---|---|
| `tendercare-web` | [artificialiman/tendercare-web](https://github.com/artificialiman/tendercare-web) | Public site |
| `tendercare-teacher` | this repo | Staff dashboard, roster management |
| `tendercare-portal` | *(next)* | Result/transcript portal + directory |

This repo is **private** — it handles real student data (scores, remarks,
names). `tendercare-web` and `tendercare-portal` only ever have **read**
access to `students` (enforced by RLS, not just app-level convention — see
`supabase/migrations/0002_rls_policies.sql`), and only to rows where
`active = true`.

## The roster is the point of this app

Every student in the whole suite exists in exactly one place: the
`students` table, defined in `supabase/migrations/0001_core_schema.sql`.
`src/routes/roster/+page.svelte` is where a teacher adds or removes a
student — that single write is what shows up (or disappears) on the
result/transcript portal, the directory, and the public site's yearbook,
because those apps have nowhere else to read a student from.

Two removal paths, deliberately different:
- **Remove** (soft delete, `active = false`) — the normal path. Student
  disappears from every app immediately; their scores and academic history
  stay intact and recoverable via **Restore**.
- **Permanently erase** (real `DELETE`, behind a confirmation step) — for
  actual mistakes (duplicate entry, wrong school). This cascades through
  `ON DELETE CASCADE` and genuinely removes their scores, remarks, portal
  credentials, and feed activity. Not reversible.

## Roster data provenance

Seeded from `Teacher-care`'s `tcc_broadsheet.html` (376 students, 12
classes) — chosen as authoritative after cross-checking against every other
candidate "admin broadsheet" file in that repo:

- `sheet.html` (2025/2026, also claimed 376) has a column-shift bug in its
  SS1 Actuarial section — it returns first-name-only students that actually
  belong to SS3 Science. Not used.
- `admin-broadsheet.html` has the same shift bug and is short 2 students
  (374). Not used.
- `admin_broadsheet.html` (374) agrees with `tcc_broadsheet.html` on **all
  374 names they share, zero spelling disagreements** — it's just missing
  `TCH-2025-074` and `TCH-2025-323`. This cross-check is what confirms
  `tcc_broadsheet.html` rather than just picking the highest count.

See `supabase/seed/001_roster_2024_2025.sql`.

## Score data: loaded as-is, known to be messy

`supabase/seed/002_scores_asis.sql` (2,826 rows) comes from 9 CSV exports
in the old `Teacher-care` repo — each in a **different schema** (long
format, wide format with `_CA`/`_Exam` suffixes, slash-delimited
`CA/Exam/Total` in a single cell, pipe-delimited `CA|Exam|Total`, one file
with placeholder rows reading literally "No scores available"). Per
instruction, this was loaded **verbatim, not reconciled** — unlike the
roster, no attempt was made to pick a single correct value where sources
disagree. Known issues, left as-is on purpose:

- **69 distinct raw subject labels** for what's really more like 25–30
  actual subjects (`Maths`/`MATHS`/`Mathematics`, `Eng`/`ENGLISH`/`English`,
  etc.) — not normalized into the canonical `subjects` list from the
  roster seed. Real cleanup work, not something to guess at now.
- **12 student names in the CSVs don't match the verified 376-student
  roster** (`Adio Daniel`, `Ilo Joseph`, `Ilo David`, and 9 others) — their
  143 score rows were skipped rather than inserted with a broken foreign
  key. Listed in full in the SQL file's header comment. Some of these look
  like new/transferred-in students per the source files' own notes (one
  CSV's literal first line says it "combines... newly added students") —
  worth checking whether they should be added to the roster rather than
  assumed to be typos.
- **Inconsistent term structure per file** — some files specify no term at
  all, one has two terms in wide-format columns. Term IDs carry a
  `(filename.csv)` suffix where the source didn't specify a term, so
  where the same student+subject appears in more than one file, both rows
  are kept rather than one overwriting the other.

`scripts/parse_scores.py` does the parsing and can be re-run once the
source data itself gets cleaned up.



This needs a real Supabase project — not yet provisioned/connected as of
this commit.

```bash
cp .env.example .env    # fill in PUBLIC_SUPABASE_URL / PUBLIC_SUPABASE_ANON_KEY
```

Then apply the schema in order:

```bash
supabase db push        # or run the migrations/ and seed/ SQL files directly
                         # in the Supabase SQL editor, in numeric order
```

## Stack

- SvelteKit 2 (Svelte 5, runes) + TypeScript
- `adapter-vercel` — this app needs SSR (authenticated writes), unlike
  `tendercare-web`'s static build
- `@supabase/supabase-js`, RLS-enforced roles (`staff` vs. read-only)

## Status

Scaffolded: schema, RLS policies, seed data, and the roster add/remove/
restore/erase screen (`/roster`). Type-checks clean, builds clean with
placeholder env vars.

**Not yet done:** score-entry/broadsheet screens (the `teacher-dashboard.html`
in the old `Testy` repo turned out to be a disconnected demo shell —
references a `js/tcc-data.js` that doesn't exist anywhere — so this is being
rebuilt against the real data model rather than ported from that file),
staff authentication/login, and the actual Supabase project provisioning
(blocked on connecting a real project — nothing here has been run against
live data yet).

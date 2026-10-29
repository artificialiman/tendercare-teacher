# tendercare-teacher

Staff dashboard for Tendercare Comprehensive College — broadsheets, score
entry, and the **single source of truth for the student roster**.

## Current state: hardcoded data, no sign-in, no network calls

The teacher app does not fetch anything. The school's real classes, subjects,
class-subject links, roster (377 students as of the 2025/26 snapshot)
and terms are compiled into the app by `scripts/generate_teacher_data.py`
(output: `src/lib/teacherData.ts`). Sources: `supabase/seed/001_roster_*.sql`
and `scripts/snapshot/live_admin_snapshot.json` (what was found in the Supabase
project reachable at the time -- note it is pre-promotion; see the file's
`_about`). Re-run the script after either changes.

- **Who I am:** the teacher ticks their subjects and classes once on the home
  page; that is kept in this browser (`src/lib/teacherIdentity.ts`). There is
  no staff list or admin-made assignment data yet, so nothing is guessed.
- **What teachers can do:** enter CA/exam scores for their subject-class sheets,
  add/remove/transfer students between arms, add arms, and open a read-only
  **Broadsheet** of every subject they are concerned with (all subjects in a
  class they are class teacher of; otherwise only their own).
- **Changes stay on the device** (`src/lib/localState.ts`, localStorage). They
  are not sent anywhere; syncing to the admin database arrives with real auth.
- **Admin** (staff, assignments, promotion, intake, analytics) lives in the
  separate `tendercare-admin` app.
- `supabase/` is kept as the reference schema for when a backend returns.

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

Seeded from `UTMEDaily`'s `Tendercare/Directory/student-directory.html`
(376 students, 12 classes) — confirmed authoritative directly.

An earlier version of this seed used `Teacher-care`'s `tcc_broadsheet.html`
instead, cross-checked against `admin_broadsheet.html` for confidence. That
cross-check turned out to be worthless: both files share the *same*
column-shift bug from `TCH-2025-234` onward (143 students — the entire SS1
Actuarial through SS3 Actuarial range), so them agreeing with each other
didn't actually prove anything. `student-directory.html` doesn't have that
shift and was confirmed correct directly, so it replaced `tcc_broadsheet.html`
as the source. Full comparison and reasoning in
`supabase/seed/001_roster_2024_2025.sql`'s header comment.

Class/subject structure (which classes exist, which subjects each class
takes) still comes from `tcc_broadsheet.html` — that part was never
affected, only the per-student ID-to-name mapping was.

## Score data: loaded as-is, known to be messy

`supabase/seed/002_scores_asis.sql` (2,847 rows) comes from 9 CSV exports
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
- **10 student names in the CSVs don't match the roster** (`Adio Daniel`,
  `Ilo Joseph`, `Ilo David`, and 7 others) — their 122 score rows were
  skipped rather than inserted with a broken foreign key. Listed in full
  in the SQL file's header comment. Some of these look like new/
  transferred-in students per the source files' own notes (one CSV's
  literal first line says it "combines... newly added students") — worth
  checking whether they should be added to the roster rather than assumed
  to be typos.
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

## Working offline, and getting scores off the phone

The app needs a connection once, to install itself. After that it opens and works
with none: every address loads from a copy stored on the phone (`src/service-worker.ts`),
the data is compiled in, and what a teacher types is saved on the phone.

**What is stored where (all in the browser, nothing sent anywhere)**

| Record | Holds | Survives a rebuild? |
|---|---|---|
| `tc_score_edits` | only the scores typed on this phone: student, subject, term, CA/Exam, and the time each field was typed | yes -- independent of the data version |
| `tc_local_state` | roster / class / remark changes made on this phone | no -- dropped when the shipped data changes (`DATA_VERSION`) |
| `…_bak` | the previous version of each record, used if the current one is unreadable | |
| `…_corrupt` | a record that could not be read, kept aside (never overwritten) | |

Every save is read back and compared; a failed one (storage full, browser blocking
storage, a write silently dropped) is shown to the teacher, on the sheet and on the
dashboard, instead of being assumed to have worked. The browser is also asked to
treat the storage as persistent so it is not cleared under space pressure.

**Updates never swap the app under an open tab.** A new version downloads in the
background and waits; it starts the next time every tab of the app has been closed.
Only the very first install takes over at once. Deploying during exam week is
therefore safe for people mid-entry -- but also means a fix reaches a phone only after
the app has been closed and reopened.

**Handing scores in.** The dashboard's *On this device* card makes a **scores file**
(JSON: this phone's typed scores, with the student and subject name next to each id,
and a checksum). *Send scores file* opens the phone's share sheet (WhatsApp, email,
Bluetooth); *Save a copy* downloads it; *Restore from a file* merges one back in
(newest-typed value wins per field, nothing is ever deleted -- also how a wiped or
replaced phone is recovered).

**Merging the files at the school** (no server, same route as roster changes):

```
python3 scripts/scores/ingest.py received/*.json     # validate + merge; prints a report
python3 scripts/generate_teacher_data.py             # bundle the merged scores
# commit + deploy
```

`ingest.py` refuses a damaged file whole; rejects entries whose student id is not on
the roster, whose name disagrees with the roster, or whose score is not 0-100; warns
when a student has changed class; merges per field newest-typed-wins; and lists every
conflict (same field typed differently on two phones) for a person to look at. It is
safe to run twice. Output: `scripts/scores/term_scores/<term>.json` (the school's
record), `applied/` (the files received), `reports/` (what happened). After the next
build, every phone receives the merged scores; a phone's own typing overrides them
only if it was typed later.

**The current term** is set by `CURRENT_TERM_ID` in `scripts/generate_teacher_data.py`
(now `2026-2027-T1`). Scores are filed under it -- change it at the start of each term.

**Tests**

```
npx tsx scripts/tests/local_state_test.mts       # device storage: failures, corruption, merge (10)
python3 scripts/tests/scores_ingest_test.py      # the school-side merge (10)
npm run build && python3 scripts/tests/browser_test.py   # real Chromium: offline, sheet, scores file (35)
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

## How a roster change reaches every app (no database involved)

One canonical file holds the roster: `scripts/roster/students.json` (post-
promotion, post-intake; statuses `active | graduated | left`). Nothing else is
edited by hand. When assigned staff change the student list:

1. **Staff prepare the change** in the admin app (*Add Students* downloads a
   `roster-change-YYYY-MM-DD.json`; moves/removals use the same format).
2. **Tech team applies it:** `python3 scripts/roster/apply_changes.py change.json`
   -- validates everything, assigns gap-free IDs, all-or-nothing, archives the
   file in `scripts/roster/applied/`.
3. **Publish:** `python3 scripts/roster/publish.py --portal ../tendercare-portal
   --web ../tendercare-web --admin ../tendercare-admin` hardcodes the result
   into every app: the teacher app's data, the report-pipeline skeletons, the
   portal's student directory, the portal's frozen graduate reports, the web
   alumni archive, and the admin app's class list. It is idempotent.
4. Commit each repo and let it deploy. No server watches for changes.

`scripts/intake/` and `scripts/snapshot/` are the inputs the canonical file
was bootstrapped from (`bootstrap_students.py`, one-time).

Heads-up: a new teacher-app build changes `DATA_VERSION`, so each device drops
its *saved roster edits* (scores are always kept) -- by design in
`localState.ts`. Publish roster changes before teachers make their own.

Not yet in the canonical file: the current term (the app still says
2025/2026 Term 3) and class-subject links for `SS1 Unassigned` (students wait
there for a department).

## Status: no sign-in
There is no sign-in and no Supabase client in this app. Real auth is to be
added later, together with a way to sync the changes saved on each device.
`supabase/migrations/0021`-`0023` (admission tracking + bulk intake, staff
assignments, and a switchable open-access policy) are written but **not
applied**; they are for when a database comes back. Nothing above needs them.

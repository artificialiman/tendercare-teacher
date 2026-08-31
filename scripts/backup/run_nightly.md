# Running this on a schedule

`.github/workflows/nightly-backup.yml` runs `export_backup.py` nightly
(2am UTC) and commits the dated snapshot straight into
`scripts/backup/exports/` in this repo — now safe, since the repo is
private.

## One-time setup — do this in GitHub's UI, never in chat

Repo Settings → Secrets and variables → Actions → New repository secret:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

The service-role key bypasses RLS entirely — it's a strictly more
dangerous credential than the anon key or even an admin login. Paste it
directly into GitHub's secret field, never into a chat, a commit, or a
workflow file's `env:` block. GitHub secrets are write-only once saved —
nobody, including repo admins, can read a saved secret's value back out
through the UI or API afterward, only overwrite it.

## What's still an open, smaller decision

**Retention on the backups themselves** — right now every nightly
snapshot is kept forever, uncompressed JSON. Fine at current scale (a
single school's roster/scores/staff is small — low hundreds of KB per
snapshot), worth revisiting once a year or two of nightly history has
accumulated. A simple later fix: keep daily for 30 days, then thin to
one-per-month.

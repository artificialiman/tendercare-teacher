# Running this on a schedule — not wired up yet, on purpose

`export_backup.py` is safe to run right now, by hand, from a machine
that has `SUPABASE_SERVICE_ROLE_KEY` set locally and never commits it
anywhere. What's deliberately **not** built yet is the automated,
scheduled half — a GitHub Actions workflow that runs this nightly and
commits the result — because doing that safely needs one decision made
first:

## The blocker: `tendercare-teacher` is a public repo

The export contains real student names, scores, remarks, staff records —
exactly the data the antifail doctrine is trying to protect. Committing
that into a public repo's history on a nightly cron would be a direct,
serious data-exposure mistake — the opposite of what this backup exists
to prevent. `git log` doesn't forget; even deleting the file later
leaves it recoverable from history.

## What needs deciding before this gets automated

1. **Where does the exported data actually live?** Options, roughly in
   order of how little new infrastructure they need:
   - A **new private repo**, dedicated to backups only, with the
     narrowest possible list of collaborators.
   - A **private cloud storage bucket** (S3-compatible, or whatever the
     school already has an account with) instead of git entirely — arguably
     a better fit than a repo for something that's a series of dated
     snapshots, not code meant to be diffed/reviewed.
   - **Supabase's own storage**, if the antifail doctrine's stance
     against depending on Supabase for anything critical extends to "the
     backup of Supabase shouldn't also live in Supabase" — worth
     deciding explicitly rather than assuming either way.

2. **Where does `SUPABASE_SERVICE_ROLE_KEY` live for the scheduled job?**
   A GitHub Actions *repository secret* on whichever repo ends up running
   the workflow — never in a file, never in a workflow's `env:` block
   directly, never in a public repo's secrets even though GitHub secrets
   themselves aren't readable once set (the risk is the workflow file
   itself, or a log line, accidentally printing it).

3. **Retention on the backups themselves** — keep every nightly export
   forever, or roll old ones off after some window? (Doesn't need to
   match the antifail doctrine's per-category retention table exactly —
   this is a backup of backups, not user-facing data, so a coarser
   policy is fine — but an *implicit* answer of "whatever GitHub Actions
   minutes allow" is exactly the kind of undecided-and-therefore-risky
   state the doctrine warns against.)

Once those are answered, the workflow itself is a small addition —
intentionally not built speculatively ahead of the actual decision.

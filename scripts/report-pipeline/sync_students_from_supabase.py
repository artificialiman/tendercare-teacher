#!/usr/bin/env python3
"""
Sync the live Supabase student roster into report-pipeline/students/.

The gap this closes: report-pipeline/students/ only ever had 12
hand-added files (10 demo, 2 real) -- adding or removing a student via
tendercare-teacher's /roster had zero effect on what report-pipeline
or tendercare-portal knew about. This script is the missing link.

Read-only against Supabase, using the anon key -- the "portal and
public apps see active students only" RLS policy (active = true) on
`students` already grants this without any special credential. Writes
land as plain JSON files in this repo, same as everything else this
pipeline produces -- no live query ever happens at result-view time,
only here, at sync time.

Explicitly NOT real-time. Per direct instruction: "students wont be
added/removed every week so theres no super-live-real-time
requirement... it just needs to be an any teacher functionality that
updates everywhere without fail." Run this by hand, on a schedule, or
as a CI step on every tendercare-teacher deploy -- whichever fits;
none of those needs this script itself to change. (A genuinely live
version is possible cheaply via Supabase Realtime's postgres_changes
if that's ever wanted instead -- noted here, not built, since nothing
requires it yet.)

Usage:
    PUBLIC_SUPABASE_URL=https://your-project.supabase.co \\
    PUBLIC_SUPABASE_ANON_KEY=your-anon-key \\
    python3 sync_students_from_supabase.py

    python3 sync_students_from_supabase.py --dry-run   # report only, write nothing
"""
import argparse
import json
import os
import sys
import urllib.request
import urllib.error
from pathlib import Path

STUDENTS_DIR = Path(__file__).parent / "students"

# Every existing subject seniority level uses exactly 3 terms/year and
# seniority in years matches schema/seniority_map.json -- reused here
# so a brand-new student's skeleton file has the right number of
# (empty, undigitized) year/term slots for their class from day one,
# not just their current term.
SENIORITY_MAP_PATH = Path(__file__).parent / "schema" / "seniority_map.json"


def fetch_active_students(supabase_url: str, anon_key: str) -> list[dict]:
    """GET students where active=true, via PostgREST -- the same query
    the RLS policy is scoped for. Returns id, full_name, class_id."""
    url = f"{supabase_url}/rest/v1/students?select=id,full_name,class_id&active=eq.true&order=id.asc"
    req = urllib.request.Request(
        url,
        headers={
            "apikey": anon_key,
            "Authorization": f"Bearer {anon_key}",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"Supabase request failed: {e.code} {e.reason}", file=sys.stderr)
        print(e.read().decode(), file=sys.stderr)
        sys.exit(1)


def current_academic_year() -> str:
    """Matches create_student()'s Sept-1 boundary (see
    0007_fix_student_id_year.sql) -- not calendar year."""
    import datetime
    now = datetime.datetime.now(datetime.timezone.utc)
    start = now.year if now.month >= 9 else now.year - 1
    return f"{start}/{start + 1}"


def load_seniority_map() -> dict:
    data = json.loads(SENIORITY_MAP_PATH.read_text())
    data.pop("_comment", None)
    return data


def build_skeleton(student: dict, seniority_map: dict) -> dict:
    """A brand-new student's file: real id/name/class from Supabase,
    every term for every year of their class's seniority marked
    undigitized. No scores fabricated -- score entry is a separate,
    not-yet-built concern; this script's only job is making sure every
    currently-enrolled student HAS a file to eventually digitize into."""
    class_arm = student["class_id"]
    years_of_seniority = seniority_map.get(class_arm, 1)
    academic_year = current_academic_year()
    start_year = int(academic_year.split("/")[0])

    years = []
    for i in range(years_of_seniority):
        yr = start_year - (years_of_seniority - 1 - i)
        years.append({
            "academic_year": f"{yr}/{yr + 1}",
            "class_at_time": class_arm if i == years_of_seniority - 1 else "(prior year, not tracked yet)",
            "is_current": i == years_of_seniority - 1,
            "terms": [{"term_name": n, "digitized": False} for n in ("First", "Second", "Third")],
        })

    return {
        "student_id": student["id"],
        "full_name": student["full_name"],
        "class_arm": class_arm,
        "entry_year": years[0]["academic_year"],
        "access_code_hint": "12345678",
        "years": years,
    }


def sync(dry_run: bool = False):
    supabase_url = os.environ.get("PUBLIC_SUPABASE_URL")
    anon_key = os.environ.get("PUBLIC_SUPABASE_ANON_KEY")
    if not supabase_url or not anon_key:
        print("PUBLIC_SUPABASE_URL and PUBLIC_SUPABASE_ANON_KEY must both be set.", file=sys.stderr)
        sys.exit(1)

    STUDENTS_DIR.mkdir(exist_ok=True)
    seniority_map = load_seniority_map()

    active_students = fetch_active_students(supabase_url, anon_key)
    active_ids = {s["id"] for s in active_students}
    print(f"Supabase reports {len(active_students)} active students.")

    existing_files = {
        f.stem for f in STUDENTS_DIR.glob("*.json")
        if not f.stem.startswith("TCH-0000")  # never touch the labeled demo files
    }

    created = []
    for student in active_students:
        if student["id"] in existing_files:
            continue
        skeleton = build_skeleton(student, seniority_map)
        created.append(student["id"])
        if not dry_run:
            (STUDENTS_DIR / f"{student['id']}.json").write_text(json.dumps(skeleton, indent=2))

    # Real students whose file exists but who are no longer active in
    # Supabase (removed or soft-deleted). Per instruction: note this,
    # don't build the alumni-archive move yet -- just report it clearly
    # so nothing silently goes stale without anyone knowing.
    no_longer_active = sorted(
        existing_files - active_ids
        - {"TCH-2025-032", "TCH-2025-214"}  # the two hand-added real examples predate this script; not Supabase-backed, exempt from this check
    )

    print(f"Created {len(created)} new skeleton file(s){' (dry run -- not written)' if dry_run else ''}.")
    if created:
        for sid in created:
            print(f"  + {sid}")

    if no_longer_active:
        print(f"\n{len(no_longer_active)} file(s) exist for students no longer active in Supabase:")
        for sid in no_longer_active:
            print(f"  ? {sid}")
        print(
            "Not moved or deleted -- per instruction, these should eventually move to an "
            "alumni archive rather than being deleted (loses any scores already entered) "
            "or silently left in the active set. That archive isn't built yet; this is "
            "just the flag that it's needed."
        )

    if not created and not no_longer_active:
        print("Nothing to do -- every active student already has a file, no stale ones found.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="report what would change, write nothing")
    args = parser.parse_args()
    sync(dry_run=args.dry_run)

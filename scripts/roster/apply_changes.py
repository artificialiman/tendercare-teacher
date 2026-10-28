#!/usr/bin/env python3
"""
Apply a staff-prepared roster change file to the canonical roster
(scripts/roster/students.json). Nothing is hardcoded anywhere else yet --
run publish.py afterwards to push the result into every app.

Change file (what the admin app's "Add Students" page downloads):
{
  "academic_year": "2026/2027",
  "changes": [
    {"action": "add",    "full_name": "Okoro Chiamaka", "class_id": "SS2 Science", "admission_type": "transfer_in"},
    {"action": "add",    "full_name": "Adeyemi Tola",   "class_id": "JSS1A",       "admission_type": "intake"},
    {"action": "move",   "id": "TCH-2025-014", "class_id": "JSS3B"},
    {"action": "remove", "id": "TCH-2025-120", "reason": "withdrawn"}
  ]
}
IDs for "add" are assigned here, gap-free, continuing the session's sequence
(every id ever issued counts, graduates and leavers included). All-or-nothing:
any invalid change aborts the whole file and nothing is written.

    python3 scripts/roster/apply_changes.py change.json [--dry-run]
"""
import argparse
import json
import shutil
import sys
from datetime import date

from common import EXIT_REASONS, ROOT, load_roster, save_roster, seed_classes, next_ids


def fail(msg):
    sys.exit(f"REJECTED (nothing written): {msg}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("change_file")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    change = json.load(open(a.change_file, encoding="utf-8"))
    year = change.get("academic_year")
    if not year or not year[:4].isdigit():
        fail('"academic_year" like "2026/2027" is required')
    year_start = int(year[:4])

    doc = load_roster()
    classes = {c["id"]: c for c in seed_classes()}
    by_id = {s["id"]: s for s in doc["students"]}
    adds = []
    log = []

    for n, ch in enumerate(change["changes"], 1):
        act = ch.get("action")
        if act == "add":
            name = (ch.get("full_name") or "").strip()
            cls = ch.get("class_id")
            typ = ch.get("admission_type", "transfer_in")
            if not name:
                fail(f"change {n}: full_name missing")
            if cls not in classes:
                fail(f'change {n} ({name}): no class "{cls}". Classes: {sorted(classes)}')
            if typ not in ("intake", "transfer_in"):
                fail(f"change {n} ({name}): admission_type must be intake or transfer_in")
            c = classes[cls]
            if typ == "intake" and not (c["stage"] == "JSS" and c["level"] == 1):
                fail(f"change {n} ({name}): intake students go into a JSS1 class, not {cls}")
            if any(s["status"] == "active" and s["full_name"].lower() == name.lower() and s["class_id"] == cls
                   for s in doc["students"]) and not ch.get("allow_duplicate"):
                fail(f'change {n}: "{name}" is already active in {cls} (set "allow_duplicate": true if it really is a second pupil)')
            adds.append(dict(full_name=name, class_id=cls, admission_type=typ))
        elif act == "move":
            s = by_id.get(ch.get("id"))
            if not s or s["status"] != "active":
                fail(f'change {n}: {ch.get("id")} is not an active student')
            if ch.get("class_id") not in classes:
                fail(f'change {n}: no class "{ch.get("class_id")}"')
            log.append(f'move   {s["id"]} {s["full_name"]}: {s["class_id"]} -> {ch["class_id"]}')
            s["class_id"] = ch["class_id"]
        elif act == "remove":
            s = by_id.get(ch.get("id"))
            if not s or s["status"] != "active":
                fail(f'change {n}: {ch.get("id")} is not an active student')
            if ch.get("reason") not in EXIT_REASONS:
                fail(f'change {n}: reason must be one of {EXIT_REASONS}')
            s["status"], s["exit_reason"], s["left_on"] = "left", ch["reason"], date.today().isoformat()
            log.append(f'remove {s["id"]} {s["full_name"]} ({ch["reason"]})')
        else:
            fail(f"change {n}: unknown action {act!r}")

    ids = next_ids(doc, year_start, len(adds))
    for i, ad in zip(ids, adds):
        doc["students"].append(dict(id=i, full_name=ad["full_name"], class_id=ad["class_id"], status="active",
                                    admitted_academic_year=year, admission_type=ad["admission_type"]))
        log.append(f'add    {i} {ad["full_name"]} -> {ad["class_id"]} ({ad["admission_type"]})')

    print("\n".join(log) or "no changes")
    if a.dry_run:
        print("(dry run -- nothing written)")
        return
    doc["as_of"] = date.today().isoformat()
    save_roster(doc)
    done = ROOT / "scripts" / "roster" / "applied"
    done.mkdir(exist_ok=True)
    shutil.copy(a.change_file, done / f"{date.today().isoformat()}_{len(list(done.iterdir())) + 1:03d}.json")
    print(f"applied {len(log)} changes; archived in scripts/roster/applied/. Now run: python3 scripts/roster/publish.py")


if __name__ == "__main__":
    main()

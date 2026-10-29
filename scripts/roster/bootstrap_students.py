#!/usr/bin/env python3
"""
ONE-TIME: build scripts/roster/students.json, the canonical roster, from the
sources that existed before it:

  supabase/seed/001_roster_2024_2025.sql      376 students (2025/26 session)
  scripts/snapshot/live_admin_snapshot.json   students added since the seed
  scripts/intake/jss1_2026_2027.json          the 2026/27 JSS1 intake (58)

and the September 1st 2026 promotion, applied with the same rules as
supabase/migrations/0012_run_promotion.sql (same arm up one level, JSS3 -> SS1
Unassigned, SS3 graduates). After this, students.json is edited only through
apply_changes.py and everything else is regenerated from it by publish.py.

Refuses to overwrite an existing students.json (that would erase later changes).
"""
import json
import sys

from common import ROOT, ROSTER, promote_class, save_roster, seed_classes
import re

if ROSTER.exists():
    sys.exit(f"{ROSTER} already exists -- refusing to overwrite. Edit via apply_changes.py.")

classes = seed_classes()
sql = (ROOT / "supabase/seed/001_roster_2024_2025.sql").read_text(encoding="utf-8")
rows = [(i, n.replace("''", "'"), c) for i, n, c in re.findall(
    r"\('(TCH-\d{4}-\d{3})', '((?:[^']|'')*)', '([^']+)'\)", sql.split("insert into students", 1)[1])]
snap = json.loads((ROOT / "scripts/snapshot/live_admin_snapshot.json").read_text(encoding="utf-8"))
for i, n, c in snap["students_added"]:
    if all(r[0] != i for r in rows):
        rows.append((i, n, c))
rows.sort()

students = []
for sid, name, cls in rows:
    dest = promote_class(cls, classes)
    s = dict(id=sid, full_name=name, class_id=dest or cls, status="active" if dest else "graduated",
             admitted_academic_year=None, admission_type=None)
    if not dest:
        s["graduated_on"] = "2026-09-01"
    students.append(s)

intake = json.loads((ROOT / "scripts/intake/jss1_2026_2027.json").read_text(encoding="utf-8"))
for s in intake["students"]:
    students.append(dict(id=s["id"], full_name=s["full_name"], class_id=s["class_id"], status="active",
                         admitted_academic_year=intake["academic_year"], admission_type=intake["admission_type"]))

doc = {
    "_about": "CANONICAL roster. Edit only via scripts/roster/apply_changes.py; regenerate every hardcoded "
              "copy with scripts/roster/publish.py. status: active | graduated | left. Legacy students "
              "(before the 2026/27 session) have null admission fields on purpose -- never inferred.",
    "as_of": "2026-10-28",
    "session": "2026/2027",
    "students": students,
}
save_roster(doc)
from collections import Counter
print(len(students), "students;", dict(Counter(s["status"] for s in students)))
print(dict(sorted(Counter(s["class_id"] for s in students if s["status"] == "active").items())))

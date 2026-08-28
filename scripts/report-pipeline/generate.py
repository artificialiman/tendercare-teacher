#!/usr/bin/env python3
"""
Tendercare report-card generator.

Reads one JSON file per student (schema/student_schema.json) and renders
it, plus the shared Jinja2 template, into that student's static HTML
report page. The output is a plain file -- no database call happens when
a student or parent opens it later. This is the whole point: results
stay hardcoded in the repo, and Supabase is never in the request path
for viewing a result.

Usage:
    python3 generate.py students/TCH-2025-032.json
    python3 generate.py --all        # every *.json in students/

Grades and totals are computed here, not hand-entered in the JSON, so a
student file only ever needs raw CA/exam numbers -- the same WAEC-style
band (A1 >= 75 down to F9 < 40) already used across every existing
report sheet.

CLASS COMPLETENESS GATE
------------------------
A term is only ever rendered with real numbers once at least 40% of that
student's class_arm has that same (academic_year, term_name) fully
complete -- every subject has both ca and exam filled in, no partial
entries. Below that threshold, the term renders exactly like an
undigitized one ("Record not yet digitized"), regardless of what the
JSON itself says, so a handful of early entries can never make a term
"go live" for a class before the class is actually mostly done. This
applies even in single-file mode -- it loads every sibling file in
students/ that shares the same class_arm to compute the real percentage,
not just the one file being rendered.

This is a publish gate, not a data gate: the underlying JSON keeps
whatever was actually entered. Nothing here mutates a student's file --
only what gets written to output/ is affected. Re-running generate.py
after more of the class is entered will pick the term up automatically
once it crosses 40%, no manual unlock step needed.
"""
import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

from jinja2 import Environment, FileSystemLoader

ROOT = Path(__file__).parent
TEMPLATES = ROOT / "templates"
STUDENTS = ROOT / "students"
OUTPUT = ROOT / "output"

GRADE_BANDS = [
    (75, "A1", "ga1"), (70, "B2", "gb2"), (65, "B3", "gb3"),
    (60, "C4", "gc4"), (55, "C5", "gc5"), (50, "C6", "gc6"),
    (45, "D7", "gd7"), (40, "E8", "ge8"), (0, "F9", "gf9"),
]

REMARKS = {
    "A1": "Excellent", "B2": "Very Good", "B3": "Good",
    "C4": "Credit", "C5": "Credit", "C6": "Credit",
    "D7": "Pass", "E8": "Pass", "F9": "Fail",
}

CLASS_PUBLISH_THRESHOLD = 0.40


def grade_for(total):
    for floor, label, css in GRADE_BANDS:
        if total >= floor:
            return label, css
    return "F9", "gf9"


def remark_for(total):
    """Qualitative band only (e.g. 'Excellent') -- for any consumer that
    shouldn't expose the underlying number, like the awards page."""
    label, _ = grade_for(total)
    return REMARKS[label]


def term_is_complete(term: dict) -> bool:
    """A term counts toward class completeness only if every subject has
    both ca and exam filled -- a partially-entered term (some subjects
    still pending) does not count as done for gating purposes, even
    though the template still renders individual pending subjects fine
    once a term does clear the gate."""
    if not term.get("digitized"):
        return False
    subjects = term.get("subjects", [])
    if not subjects:
        return False
    return all(s.get("ca") is not None and s.get("exam") is not None for s in subjects)


def load_all_students() -> list[dict]:
    files = sorted(STUDENTS.glob("*.json"))
    return [json.loads(f.read_text()) for f in files]


def compute_class_term_stats(all_students: list[dict]) -> dict:
    """(class_arm, academic_year, term_name) -> {'complete': n, 'total': n, 'pct': float}.
    'total' is every student in that class_arm found in students/, not
    just the ones with data for that term -- an empty/undigitized term
    for a classmate still counts against the class's completeness."""
    class_rosters = defaultdict(set)  # class_arm -> {student_id, ...}
    term_complete = defaultdict(set)  # (class_arm, year, term) -> {student_id, ...}

    for student in all_students:
        class_arm = student["class_arm"]
        sid = student["student_id"]
        class_rosters[class_arm].add(sid)
        for year in student.get("years", []):
            for term in year.get("terms", []):
                key = (class_arm, year["academic_year"], term["term_name"])
                if term_is_complete(term):
                    term_complete[key].add(sid)

    stats = {}
    all_keys = set(term_complete.keys())
    for student in all_students:
        class_arm = student["class_arm"]
        for year in student.get("years", []):
            for term in year.get("terms", []):
                all_keys.add((class_arm, year["academic_year"], term["term_name"]))

    for key in all_keys:
        class_arm = key[0]
        class_size = len(class_rosters[class_arm])
        complete = len(term_complete.get(key, set()))
        pct = (complete / class_size) if class_size else 0.0
        stats[key] = {"complete": complete, "total": class_size, "pct": pct}
    return stats


def compute_term(term, gate_key, class_stats, warnings):
    """Fill in per-subject totals/grades and the term summary band, in
    place, from raw ca/exam numbers -- but only if this class+term has
    cleared the 40% class-completeness gate. Below that, the term is
    forced back to undigitized for rendering, same as a term nobody has
    touched yet."""
    if not term.get("digitized"):
        return term

    stat = class_stats.get(gate_key, {"complete": 0, "total": 0, "pct": 0.0})
    if stat["pct"] < CLASS_PUBLISH_THRESHOLD:
        class_arm, academic_year, term_name = gate_key
        warnings.append(
            f"  BLOCKED: {class_arm} {academic_year} {term_name} term is "
            f"{stat['pct']*100:.0f}% complete ({stat['complete']}/{stat['total']} "
            f"students) -- below the {CLASS_PUBLISH_THRESHOLD*100:.0f}% publish "
            f"threshold. Rendering as not-yet-digitized until the rest of the "
            f"class catches up."
        )
        return {"term_name": term["term_name"], "digitized": False}

    total_score = 0
    graded_count = 0
    for s in term.get("subjects", []):
        if s.get("ca") is not None and s.get("exam") is not None:
            s["total"] = s["ca"] + s["exam"]
            s["grade"], s["grade_class"] = grade_for(s["total"])
            total_score += s["total"]
            graded_count += 1
        else:
            s["total"] = None
            s["grade"] = None
            s["grade_class"] = None

    term["subject_count"] = len(term.get("subjects", []))
    term["total_score"] = total_score
    term["max_score"] = graded_count * 100
    term["average"] = round(total_score / graded_count, 2) if graded_count else 0
    return term


def find_current_term_id(years):
    """The most recent digitized term across all years, or the most
    recent term at all if none are digitized yet -- matches the existing
    files' behavior of opening on the latest real record. Runs on the
    already-gated terms, so a class-blocked term is correctly treated as
    not-yet-digitized here too, same as any other undigitized term."""
    last_id = None
    last_digitized_id = None
    for yi, year in enumerate(years):
        for ti, term in enumerate(year["terms"], start=1):
            term_id = f"y{yi}t{ti}_{year['academic_year'].replace('/', '-')}"
            last_id = term_id
            if term.get("digitized"):
                last_digitized_id = term_id
    return last_digitized_id or last_id


def render_student(data: dict, class_stats: dict, warnings: list) -> str:
    class_arm = data["class_arm"]
    for year in data["years"]:
        gated_terms = []
        for t in year["terms"]:
            gate_key = (class_arm, year["academic_year"], t["term_name"])
            gated_terms.append(compute_term(t, gate_key, class_stats, warnings))
        year["terms"] = gated_terms

    env = Environment(loader=FileSystemLoader(str(TEMPLATES)), autoescape=False)
    template = env.get_template("report_template.html.j2")

    context = dict(data)
    context.setdefault("access_code_hint", "12345678")
    context["current_term_id"] = find_current_term_id(data["years"])
    return template.render(**context)


def generate_one(json_path: Path, class_stats: dict, warnings: list):
    data = json.loads(json_path.read_text())
    html = render_student(data, class_stats, warnings)
    out_path = OUTPUT / f"{data['student_id']}.html"
    out_path.write_text(html)
    print(f"wrote {out_path} ({len(html):,} bytes)")


def print_class_summary(class_stats: dict):
    print("\nClass completeness (this run's gate check):")
    for (class_arm, year, term), stat in sorted(class_stats.items()):
        status = "PUBLISHED" if stat["pct"] >= CLASS_PUBLISH_THRESHOLD else "blocked"
        print(
            f"  {class_arm:15s} {year} {term:7s} "
            f"{stat['complete']}/{stat['total']} ({stat['pct']*100:.0f}%) -- {status}"
        )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("path", nargs="?", help="a single student JSON file")
    parser.add_argument("--all", action="store_true", help="render every students/*.json")
    args = parser.parse_args()

    OUTPUT.mkdir(exist_ok=True)

    # Class completeness needs the whole roster in students/ regardless of
    # whether we're rendering one file or all of them -- a single student's
    # publish status still depends on their classmates.
    all_students = load_all_students()
    if not all_students:
        print("No student JSON files found in students/", file=sys.stderr)
        sys.exit(1)
    class_stats = compute_class_term_stats(all_students)

    warnings = []
    if args.all:
        for f in sorted(STUDENTS.glob("*.json")):
            generate_one(f, class_stats, warnings)
    elif args.path:
        generate_one(Path(args.path), class_stats, warnings)
    else:
        parser.print_help()
        return

    if warnings:
        print("\nClass-completeness gate held back the following terms:")
        for w in dict.fromkeys(warnings):  # de-dupe, preserve order
            print(w)

    print_class_summary(class_stats)


if __name__ == "__main__":
    main()

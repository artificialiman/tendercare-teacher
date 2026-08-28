#!/usr/bin/env python3
"""
Per-class-arm academic awards, for tendercare-web's awards page.

Reuses generate.py's class-completeness gate and grade/remark logic
rather than reimplementing either: a class-arm only produces an award
list once it has a term that clears the same 40%-complete threshold
that gates individual result sheets, and standing is shown as a
qualitative remark band ("Excellent", "Very Good", ...) via the same
REMARKS table generate.py uses for individual subjects -- never the raw
number. This is deliberate, not an oversight: an awards page names who
did well, it doesn't publish anyone's actual average. Anyone wanting a
specific number still has to go through the gated, individually-
accessed result sheet, not a public leaderboard.

Each entry carries student_id (not just name) so tendercare-web can
show that student's portrait, looked up by ID -- e.g.
`{base}/img/portraits/{student_id}.jpg`, with a placeholder fallback
for whichever students don't have one uploaded yet (portraits are a
separate, manually-provisioned asset -- see the admin-media-upload note
in the invariants doc -- not something this script can generate).

EXTENSIBLE BY CATEGORY
-----------------------
Output is structured as `categories.<category_id>` rather than a flat
per-class dict, because "top 3 by overall average" is meant to be the
first of several award categories, not the only one -- per-subject and
per-skill awards are coming once those categories are actually defined
(deliberately not guessed at here). `overall_average` below is the
reference implementation: a new category function should follow the
same shape (gate-checked, remark-banded, portrait-by-ID, no raw
numbers) and get registered in CATEGORIES at the bottom. Nothing about
the class-completeness gate or the remark-not-number rule is specific
to "overall average" -- both should carry over to whatever categories
get added.

Usage:
    python3 compute_awards.py            # writes output/awards.json
"""
import json
from datetime import datetime, timezone
from pathlib import Path

from generate import (
    OUTPUT,
    CLASS_PUBLISH_THRESHOLD,
    load_all_students,
    compute_class_term_stats,
    term_is_complete,
    remark_for,
)

TERM_ORDER = {"First": 1, "Second": 2, "Third": 3}


def term_sort_key(academic_year: str, term_name: str):
    """Sortable key so 'latest term' comparisons work correctly across
    years, e.g. 2025/2026 Second > 2024/2025 Third."""
    start_year = academic_year.split("/")[0]
    return (start_year, TERM_ORDER.get(term_name, 0))


def latest_published_term(class_arm: str, class_stats: dict):
    """The most recent (academic_year, term_name) for this class_arm
    that clears the 40% gate, or None if the class has no published
    term yet."""
    published = [
        (year, term)
        for (arm, year, term), stat in class_stats.items()
        if arm == class_arm and stat["pct"] >= CLASS_PUBLISH_THRESHOLD
    ]
    if not published:
        return None
    return max(published, key=lambda yt: term_sort_key(*yt))


def student_average_for_term(student: dict, academic_year: str, term_name: str):
    """This student's average for exactly this (academic_year, term_name),
    or None if they don't have a complete entry for it -- an incomplete
    student can't be ranked even if their class overall published. Used
    only for internal ranking -- never exposed directly in output."""
    for year in student.get("years", []):
        if year["academic_year"] != academic_year:
            continue
        for term in year["terms"]:
            if term["term_name"] != term_name:
                continue
            if not term_is_complete(term):
                return None
            subjects = term["subjects"]
            total = sum(s["ca"] + s["exam"] for s in subjects)
            return round(total / len(subjects), 2)
    return None


def category_overall_average(all_students: list, class_stats: dict) -> dict:
    """Reference category: top 3 by overall average, per class-arm.
    See module docstring for what a new category function should
    preserve (gate, remark-not-number, portrait-by-ID)."""
    class_arms = sorted({s["class_arm"] for s in all_students})
    classes = {}
    for class_arm in class_arms:
        latest = latest_published_term(class_arm, class_stats)
        if latest is None:
            continue  # no published term for this class yet -- no entry, not a guess
        academic_year, term_name = latest

        ranked = []
        for student in all_students:
            if student["class_arm"] != class_arm:
                continue
            avg = student_average_for_term(student, academic_year, term_name)
            if avg is not None:
                ranked.append((avg, student))

        ranked.sort(key=lambda pair: pair[0], reverse=True)
        if ranked:
            classes[class_arm] = {
                "academic_year": academic_year,
                "term_name": term_name,
                "top3": [
                    {
                        "student_id": student["student_id"],
                        "name": student["full_name"],
                        "remark": remark_for(avg),
                    }
                    for avg, student in ranked[:3]
                ],
            }
    return {"label": "Overall Academic Average", "classes": classes}


# Register new categories here once their criteria are defined. Each
# should return {"label": ..., "classes": {...}} in the same shape as
# category_overall_average, or a different top-level shape if the
# category isn't class-scoped (a school-wide award, say) -- this
# dict is the only place that needs to change to add one.
CATEGORIES = {
    "overall_average": category_overall_average,
}


def main():
    all_students = load_all_students()
    if not all_students:
        print("No student JSON files found in students/")
        return
    class_stats = compute_class_term_stats(all_students)

    categories_out = {}
    for category_id, fn in CATEGORIES.items():
        categories_out[category_id] = fn(all_students, class_stats)

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "categories": categories_out,
    }

    OUTPUT.mkdir(exist_ok=True)
    out_path = OUTPUT / "awards.json"
    out_path.write_text(json.dumps(payload, indent=2))

    total_published_classes = sum(
        len(cat["classes"]) for cat in categories_out.values() if "classes" in cat
    )
    if total_published_classes == 0:
        print("No class-arm has a published term in any category yet -- awards.json")
        print("written with empty categories. Expected until real score data")
        print("replaces the current demo set.")
    else:
        print(f"wrote {out_path}")
        for category_id, cat in categories_out.items():
            print(f"  {category_id} ({cat['label']}):")
            for class_arm, data in cat.get("classes", {}).items():
                names = ", ".join(f"{s['name']} ({s['remark']})" for s in data["top3"])
                print(f"    {class_arm} ({data['academic_year']} {data['term_name']}): {names}")


if __name__ == "__main__":
    main()

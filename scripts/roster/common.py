"""Shared helpers for the roster scripts. No network, no database."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ROSTER = ROOT / "scripts" / "roster" / "students.json"

HOLDING_CLASS = "SS1 Unassigned"   # where JSS3 lands after promotion (0012_run_promotion.sql)
EXIT_REASONS = ("withdrawn", "transferred_out", "entered_in_error", "other")


def load_roster() -> dict:
    return json.loads(ROSTER.read_text(encoding="utf-8"))


def save_roster(doc: dict) -> None:
    ROSTER.write_text(json.dumps(doc, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


def seed_classes() -> list[dict]:
    """The school's classes from the 001 seed, plus the promotion holding class."""
    sql = (ROOT / "supabase/seed/001_roster_2024_2025.sql").read_text(encoding="utf-8")
    block = sql.split("insert into classes", 1)[1].split(";", 1)[0]
    out = []
    for cid, label, arm, order in re.findall(r"\('([^']+)', '([^']+)', (null|'[^']*'), (\d+)\)", block):
        if cid.startswith("JSS"):
            stage, level, arm_v = "JSS", int(cid[3]), cid[4:]
        else:
            stage, level, arm_v = "SS", int(cid[2]), arm.strip("'")
        out.append(dict(id=cid, label=label, arm=arm_v, stage=stage, level=level, sort_order=int(order)))
    if all(c["id"] != HOLDING_CLASS for c in out):
        out.append(dict(id=HOLDING_CLASS, label="SS1 New", arm="Unassigned", stage="SS", level=1,
                        sort_order=max(c["sort_order"] for c in out) + 1))
    return out


def class_order() -> dict[str, int]:
    return {c["id"]: c["sort_order"] for c in seed_classes()}


def promote_class(class_id: str, classes: list[dict]) -> str | None:
    """Where a student in class_id goes on September 1st. None = graduates."""
    c = next(x for x in classes if x["id"] == class_id)
    if c["stage"] == "SS" and c["level"] == 3:
        return None
    if c["stage"] == "JSS" and c["level"] == 3:
        return HOLDING_CLASS
    if c["stage"] == "JSS":
        return f"JSS{c['level'] + 1}{c['arm']}"
    return f"SS{c['level'] + 1} {c['arm']}"


def next_ids(doc: dict, year_start: int, count: int) -> list[str]:
    """Gap-free ids continuing the sequence for a session, counting EVERY student ever issued."""
    prefix = f"TCH-{year_start}-"
    used = [int(s["id"].split("-")[2]) for s in doc["students"] if s["id"].startswith(prefix)]
    start = (max(used) if used else 0) + 1
    return [f"{prefix}{n:03d}" for n in range(start, start + count)]

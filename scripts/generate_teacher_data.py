#!/usr/bin/env python3
"""
Regenerates src/lib/teacherData.ts from the real data:
  supabase/seed/001_roster_2024_2025.sql   classes, subjects, class_subjects, students
  scripts/snapshot/live_admin_snapshot.json what admin changed in the live project
                                            since the seed (added students, current terms)
  supabase/seed/002_scores_asis.sql        old 2024/25 scores -- OFF by default, see below

Nothing is invented. Run from the repo root:  python3 scripts/generate_teacher_data.py

Two judgement calls live in the constants below, on purpose, so they are
one-line edits rather than buried in code:

  INCLUDE_SEED_SCORES  Old 2024/25 scores from 002. Off: the live database has
                   none, and every row shipped is something a phone must load.
  CURRENT_TERM_ID  Normally taken from the live snapshot's is_current flag.
  SUBJECT_ALIASES  002 was loaded "as-is" and uses many spellings for the same
                   subject. Rows are matched to the clean 001 subject list by
                   exact name, then case/whitespace-insensitive name, then this
                   map. Anything still unmatched is skipped and listed in the
                   report printed at the end -- never guessed.
"""
import json, re, sys
from pathlib import Path

INCLUDE_SEED_SCORES = False  # the live project holds no scores; 2024/25 rows only add bundle weight
CURRENT_TERM_ID = None       # None -> use the term marked current in the live snapshot
SUBJECT_ALIASES: dict[str, str] = {
    # Unambiguous abbreviations/spellings of a subject on the clean list.
    'Math': 'Mathematics', 'Maths': 'Mathematics', 'MATHS': 'Mathematics',
    'Eng': 'English', 'Hist': 'History', 'Lit': 'Literature', 'Fr': 'French',
    'Eco': 'Economics', 'Acc': 'Accounting', 'Comm': 'Commerce',
    'Mkt': 'Marketing', 'Bus': 'Business Studies', 'Govt': 'Government',
    'Yor': 'Yoruba', 'DataProc': 'Data Processing', 'C.C.A': 'CCA',
    'P.H.E': 'PHE', 'Digital Tech': 'DT', 'DIGITAL TECH': 'DT', 'Dig': 'DT',
    'P.H.Y (Physics)': 'Physics',
    'N.V': 'NVE', 'Nat': 'NVE', 'NATIONAL VALUE': 'NVE',
    # Deliberately NOT mapped (could mean more than one subject) -- they stay
    # in the skipped report until you confirm: BST / B.S.T / BST 1 / BST 2,
    # Civic / CIVIC / Civic Education, CRS/IRS / CRS IRS / IRS CRS,
    # Agric F.M / Agric or FMaths, P.V.S / PVS / PreVoc.
}

root = Path(__file__).resolve().parent.parent
roster_sql = (root / 'supabase/seed/001_roster_2024_2025.sql').read_text()
scores_sql = (root / 'supabase/seed/002_scores_asis.sql').read_text()

def block(sql: str, start: str, end: str) -> str:
    return sql.split(start, 1)[1].split(end, 1)[0]

# --- classes -----------------------------------------------------------
classes = []
for cid, label, arm, order in re.findall(
        r"\('([^']+)', '([^']+)', (null|'[^']*'), (\d+)\)",
        block(roster_sql, 'insert into classes', ';')):
    if cid.startswith('JSS'):
        stage, level, arm_v = 'JSS', int(cid[3]), cid[4:]
    else:  # derivation rule from 0011_extensible_classes.sql
        stage, level, arm_v = 'SS', int(cid[2]), arm.strip("'")
    classes.append(dict(id=cid, label=label, arm=arm_v, stage=stage, level=level, sort_order=int(order)))

# --- subjects ----------------------------------------------------------
subject_names = re.findall(r"^\('([^']+)'\)", block(roster_sql, 'insert into subjects', 'on conflict'), re.M)
def sid(name: str) -> str:
    return re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')
subjects = [dict(id=sid(n), name=n) for n in subject_names]
by_exact = {n: sid(n) for n in subject_names}
by_fold = {re.sub(r'\s+', ' ', n.strip().lower()): sid(n) for n in subject_names}

# --- class_subjects ----------------------------------------------------
class_subjects = [
    [c, sid(s)] for c, s in re.findall(
        r"\('([^']+)', \(select id from subjects where name = '([^']+)'\)\)",
        block(roster_sql, 'insert into class_subjects', 'on conflict'))
]

# --- students ----------------------------------------------------------
students = [list(t) for t in re.findall(
    r"\('(TCH-\d{4}-\d{3})', '((?:[^']|'')*)', '([^']+)'\)",
    roster_sql.split('insert into students', 1)[1])]
students = [[i, n.replace("''", "'"), c] for i, n, c in students]
snapshot = json.loads((root / 'scripts/snapshot/live_admin_snapshot.json').read_text())
for sid_, name_, class_ in snapshot['students_added']:
    if all(x[0] != sid_ for x in students):
        students.append([sid_, name_, class_])
students.sort(key=lambda x: x[0])
student_ids = {s[0] for s in students}

# --- terms + scores ----------------------------------------------------
terms = [dict(t) for t in snapshot['terms']]
if CURRENT_TERM_ID:
    for t in terms:
        t['is_current'] = (t['id'] == CURRENT_TERM_ID)
if sum(t['is_current'] for t in terms) != 1:
    sys.exit('exactly one term must be current')
current_id = next(t['id'] for t in terms if t['is_current'])

scores, skipped, orphan = [], {}, 0
if INCLUDE_SEED_SCORES:
    seed_terms = [dict(id=i, academic_year=y, term_number=int(n), is_current=False) for i, y, n in
                  re.findall(r"\('([^']+)', '([^']+)', (\d), false\)", block(scores_sql, 'insert into terms', 'on conflict'))]
    terms = seed_terms + terms
    for stu, subj, term, ca, exam in re.findall(
            r"\('(TCH-\d{4}-\d{3})', \(select id from subjects where name = '([^']+)'\), '([^']+)', ([\d.]+|null), ([\d.]+|null)\)",
            scores_sql.split('insert into scores', 1)[1]):
        if stu not in student_ids:
            orphan += 1
            continue
        key = SUBJECT_ALIASES.get(subj, subj)
        subj_id = by_exact.get(key) or by_fold.get(re.sub(r'\s+', ' ', key.strip().lower()))
        if not subj_id:
            skipped[subj] = skipped.get(subj, 0) + 1
            continue
        num = lambda v: None if v == 'null' else float(v)
        scores.append([stu, subj_id, term, num(ca), num(exam)])

# --- emit --------------------------------------------------------------
j = lambda o: json.dumps(o, ensure_ascii=False, separators=(',', ':'))
import hashlib
version = hashlib.md5(j([terms, classes, subjects, class_subjects, students]).encode()).hexdigest()[:10]
out = f"""// GENERATED by scripts/generate_teacher_data.py from supabase/seed/*.sql and
// scripts/snapshot/live_admin_snapshot.json. Do not edit by hand -- change those
// (or the script's constants) and re-run. Real data; nothing here is invented.

import type {{ Student }} from './roster';

export interface ClassRecord {{
	id: string;
	label: string;
	arm: string;
	stage: 'JSS' | 'SS';
	level: 1 | 2 | 3;
	sort_order: number;
}}
export interface SubjectRecord {{ id: string; name: string }}
export interface ClassSubjectRecord {{ class_id: string; subject_id: string }}
export interface ScoreRecord {{
	student_id: string;
	subject_id: string;
	term_id: string;
	ca: number | null;
	exam: number | null;
}}
export interface RemarkRecord {{
	student_id: string;
	term_id: string;
	teacher_remark: string | null;
	principal_remark: string | null;
}}
export interface TermRecord {{ id: string; academic_year: string; term_number: number; is_current: boolean }}

// Changes whenever the baseline below changes; localState.ts uses it to decide
// whether a device's saved roster edits still sit on top of the same baseline.
export const DATA_VERSION = '{version}';

export const terms: TermRecord[] = {j(terms)};
export const currentTerm: TermRecord = terms.find((t) => t.is_current)!;

export const classes: ClassRecord[] = {j(classes)};
export const subjects: SubjectRecord[] = {j(subjects)};
export const classSubjects: ClassSubjectRecord[] = ({j(class_subjects)} as [string, string][]).map(
	([class_id, subject_id]) => ({{ class_id, subject_id }})
);

export const students: Student[] = ({j(students)} as [string, string, string][]).map(
	([id, full_name, class_id]) => ({{
		id,
		full_name,
		class_id,
		active: true,
		deleted_at: null,
		repeating: false,
		repeat_assigned_at: null,
		repeat_pardoned_at: null,
		portrait_url: null,
		bio: null
	}})
);

export const scores: ScoreRecord[] = ({j(scores)} as [string, string, string, number | null, number | null][]).map(
	([student_id, subject_id, term_id, ca, exam]) => ({{ student_id, subject_id, term_id, ca, exam }})
);

export const remarks: RemarkRecord[] = [];
"""
(root / 'src/lib/teacherData.ts').write_text(out)

print(f'classes {len(classes)} | subjects {len(subjects)} | class_subjects {len(class_subjects)} | students {len(students)}')
print(f'scores bundled {len(scores)} | current term {current_id}')
if orphan: print(f'  {orphan} score rows skipped: student not on roster')
if skipped:
    print(f'  {sum(skipped.values())} score rows skipped: subject name not in the clean subject list:')
    for k, v in sorted(skipped.items(), key=lambda kv: -kv[1]): print(f'    {v:4d}  {k}')

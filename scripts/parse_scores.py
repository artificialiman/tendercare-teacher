"""
Parses the 9 differently-formatted score CSVs from the Teacher-care repo
into supabase/seed/002_scores_asis.sql. Kept here so this can be re-run
once the source data is cleaned up (see the header comment in that SQL
file for the list of known issues: 12 unmatched student names, 69
un-normalized subject labels, inconsistent term structure per file).

Expects the source CSVs in ./source-teachercare/ (copy them from the
Teacher-care repo — j1a.csv, j1b.csv, j2a.csv, j2b.csv, s1act.csv,
s2act.csv, ss1a3.csv, ss1s23.csv, ss1s3.csv — plus tcc_broadsheet.html
for roster name-matching) and writes ./scores_parsed.json plus prints a
match/unmatched summary.
"""

import csv, re, io, json

# Load the verified roster for name -> id matching
roster_by_name = {}
with open('./source-teachercare/tcc_broadsheet.html') as f:
    content = f.read()
import re as re2
m = re2.search(r'const DB=(\{.*?\});', content, re2.DOTALL)
db_str = m.group(1)
class_blocks = re2.findall(r'"([^"]+)":\{"s":\[(.*?)\],"j":\[([^\]]*)\]\}', db_str)
for class_name, students_str, subjects_str in class_blocks:
    for sid, name in re2.findall(r'\["(TCH-\d+-\d+)","([^"]+)"\]', students_str):
        key = name.strip().lower()
        roster_by_name[key] = sid

import difflib

def match_student(name):
    key = name.strip().lower()
    if key in roster_by_name:
        return roster_by_name[key]
    key2 = re.sub(r'[^a-z ]', '', key)
    for k, v in roster_by_name.items():
        if re.sub(r'[^a-z ]', '', k) == key2:
            return v
    # fuzzy fallback: same known-messy-spelling situation as the roster
    # cross-check (e.g. "Chimuanya" vs "Chimuaya", "Hamzat" vs "Hazmat").
    # High cutoff (0.85) so this only catches near-identical spellings, not
    # different students.
    close = difflib.get_close_matches(key, roster_by_name.keys(), n=1, cutoff=0.85)
    if close:
        return roster_by_name[close[0]]
    return None

scores = []  # list of dicts: student_id, subject, term, ca, exam
unmatched = []

def add_score(student_name, subject, term, ca, exam):
    def clean(v):
        if v is None: return None
        v = str(v).strip()
        if v == '' or v.upper() in ('N/A', 'NO SCORES AVAILABLE', 'NO RECORDS'):
            return None
        try:
            return float(v)
        except ValueError:
            return None
    ca_c, exam_c = clean(ca), clean(exam)
    if ca_c is None and exam_c is None:
        return  # nothing to record — also filters out placeholder rows like
                 # ss1s23.csv's "No records / No scores available / N/A" rows
    sid = match_student(student_name)
    if not sid:
        unmatched.append((student_name, subject, term))
        return
    scores.append({'student_id': sid, 'subject': subject.strip(), 'term': term, 'ca': ca_c, 'exam': exam_c})

# --- j1a.csv: long format, Student Name,Subject,CA,Exam,Total ---
with open('./source-teachercare/j1a.csv', newline='') as f:
    for row in csv.DictReader(f):
        add_score(row['Student Name'], row['Subject'], '2024-2025-T1', row.get('CA'), row.get('Exam'))

# --- j1b.csv: wide format, Name,Subj_CA,Subj_Exam,Subj_Tot,... ---
with open('./source-teachercare/j1b.csv', newline='') as f:
    reader = csv.DictReader(f)
    subj_cols = {}
    for col in reader.fieldnames:
        if col == 'Name': continue
        mobj = re.match(r'(.+)_(CA|Exam)$', col)
        if mobj:
            subj, kind = mobj.groups()
            subj_cols.setdefault(subj, {})[kind] = col
    for row in reader:
        for subj, cols in subj_cols.items():
            ca = row.get(cols.get('CA'))
            exam = row.get(cols.get('Exam'))
            if ca or exam:
                add_score(row['Name'], subj.replace('_', ' '), '2024-2025-T1', ca, exam)

# --- j2a.csv: garbage preamble + markdown fence, then long format with 2 terms per row ---
with open('./source-teachercare/j2a.csv') as f:
    raw = f.read()
csv_start = raw.index('Student Name,Subject')
csv_end = raw.rindex('```')
csv_text = raw[csv_start:csv_end]
for row in csv.DictReader(io.StringIO(csv_text)):
    name = row.get('Student Name', '').strip('"')
    subj = row.get('Subject', '').strip('"')
    if row.get('2nd Term CA') or row.get('2nd Term Exam'):
        add_score(name, subj, '2024-2025-T2', row.get('2nd Term CA'), row.get('2nd Term Exam'))
    if row.get('3rd Term CA') or row.get('3rd Term Exam'):
        add_score(name, subj, '2024-2025-T3', row.get('3rd Term CA'), row.get('3rd Term Exam'))

# --- j2b.csv: wide format, Name,Subj_CA1,Subj_CA2,Subj_Tot,...,Overall_Avg ---
with open('./source-teachercare/j2b.csv', newline='') as f:
    reader = csv.DictReader(f)
    subj_cols = {}
    for col in reader.fieldnames:
        if col in ('Name', 'Overall_Avg'): continue
        mobj = re.match(r'(.+)_(CA1|CA2)$', col)
        if mobj:
            subj, kind = mobj.groups()
            subj_cols.setdefault(subj, {})[kind] = col
    for row in reader:
        for subj, cols in subj_cols.items():
            ca1 = row.get(cols.get('CA1'))
            ca2 = row.get(cols.get('CA2'))
            # CA1+CA2 = two continuous-assessment components, no separate exam column here
            if ca1 or ca2:
                add_score(row['Name'], subj, '2024-2025-T1', ca1, ca2)

# --- s1act.csv / ss1a3.csv (near-duplicates): ID,NAME,Subj_CA,Subj_EXAM,Subj_TOTAL,... ---
for fname in ['s1act.csv', 'ss1a3.csv']:
    with open(f'./source-teachercare/{fname}', newline='') as f:
        reader = csv.DictReader(f)
        subj_cols = {}
        for col in reader.fieldnames:
            if col in ('ID', 'NAME'): continue
            mobj = re.match(r'(.+)_(CA|EXAM)$', col)
            if mobj:
                subj, kind = mobj.groups()
                subj_cols.setdefault(subj, {})[kind] = col
        for row in reader:
            name = row.get('NAME')
            if not name: continue
            for subj, cols in subj_cols.items():
                ca = row.get(cols.get('CA'))
                exam = row.get(cols.get('EXAM'))
                if ca or exam:
                    add_score(name, subj.replace('_', ' '), f'2024-2025-T1 ({fname})', ca, exam)

# --- s2act.csv: ID,Name,Subj1,Subj2,... each cell "CA/Exam/Total" ---
with open('./source-teachercare/s2act.csv', newline='') as f:
    reader = csv.DictReader(f)
    subj_names = [c for c in reader.fieldnames if c not in ('ID', 'Name')]
    for row in reader:
        name = row.get('Name')
        if not name: continue
        for subj in subj_names:
            cell = row.get(subj, '')
            if not cell: continue
            parts = cell.split('/')
            if len(parts) >= 2:
                add_score(name, subj, '2024-2025-T1 (s2act.csv)', parts[0], parts[1])

# --- ss1s23.csv: long format with explicit Term column, some rows are "No records" ---
with open('./source-teachercare/ss1s23.csv', newline='') as f:
    for row in csv.DictReader(f):
        name = row.get('Student Name')
        term_label = row.get('Term', '').strip()
        term_id = '2024-2025-T2' if '2nd' in term_label else ('2024-2025-T3' if '3rd' in term_label else '2024-2025-T1')
        add_score(name, row.get('Subject', ''), term_id, row.get('CA'), row.get('Exam'))

# --- ss1s3.csv: quoted, Name,Subj1,Subj2,... each cell "CA|Exam|Total" ---
with open('./source-teachercare/ss1s3.csv', newline='') as f:
    reader = csv.DictReader(f)
    subj_names = [c for c in reader.fieldnames if c not in ('Name', 'Notes')]
    for row in reader:
        name = row.get('Name')
        if not name: continue
        for subj in subj_names:
            cell = row.get(subj, '')
            if not cell: continue
            parts = cell.split('|')
            if len(parts) >= 2 and parts[0]:
                add_score(name, subj.replace('_', ' '), '2024-2025-T1 (ss1s3.csv)', parts[0], parts[1])

print(f"Total score rows parsed: {len(scores)}")
print(f"Unmatched student names: {len(unmatched)}")
for u in unmatched[:30]:
    print(" ", u)

with open('./scores_parsed.json', 'w') as f:
    json.dump({'scores': scores, 'unmatched': unmatched}, f)

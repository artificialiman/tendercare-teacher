#!/usr/bin/env python3
"""Run:  python3 scripts/tests/scores_ingest_test.py
Exercises scripts/scores/ingest.py end to end in a temp directory (the repo's
real score record is never touched)."""
import hashlib, json, os, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INGEST = ROOT / 'scripts/scores/ingest.py'
roster = json.loads((ROOT / 'scripts/roster/students.json').read_text())['students']
A, B = [s for s in roster if s['status'] == 'active' and s['class_id'] == 'JSS1A'][:2]
TERM = '2026-2027-T1'


def checksum(edits):
    return hashlib.sha256(json.dumps(edits, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()


def hand(name, teacher, edits, tamper=False):
    h = {'format': 'tendercare-scores', 'version': 1, 'exportedAt': '2026-10-29T12:00:00.000Z', 'dataVersion': 'x',
         'termId': TERM, 'device': teacher[:8] + '-device', 'teacher': {'name': teacher, 'subjectIds': ['english'], 'classIds': ['JSS1A']},
         'edits': edits, 'checksum': checksum(edits)}
    if tamper:
        h['edits'][0]['ca'] = 99
    p = tmp / name
    p.write_text(json.dumps(h))
    return p


def edit(student, subject='english', **kw):
    e = {'student_id': student['id'], 'student_name': student['full_name'], 'class_id': student['class_id'],
         'subject_id': subject, 'subject_name': subject.title(), 'term_id': TERM}
    e.update(kw)
    return e


def run(*files, dry=False):
    env = dict(os.environ, TENDERCARE_SCORES_DIR=str(tmp / 'out'))
    r = subprocess.run([sys.executable, str(INGEST), *map(str, files)] + (['--dry-run'] if dry else []), capture_output=True, text=True, env=env)
    return r.returncode, r.stdout


def record():
    f = tmp / 'out' / 'term_scores' / f'{TERM}.json'
    return {(r['student_id'], r['subject_id']): r for r in json.loads(f.read_text())['rows']} if f.exists() else {}


passed = 0


def check(name, cond, detail=''):
    global passed
    assert cond, f'{name}: {detail}'
    passed += 1
    print('  ok  ', name)


with tempfile.TemporaryDirectory() as d:
    tmp = Path(d)

    t1 = hand('t1.json', 'Mrs Ada', [edit(A, ca=20, ca_at='2026-10-29T09:00:00.000Z', exam=50, exam_at='2026-10-29T09:05:00.000Z')])
    code, out = run(t1)
    rows = record()
    check('a valid file is applied', code == 0 and rows[(A['id'], 'english')]['ca'] == 20 and rows[(A['id'], 'english')]['exam'] == 50, out)

    before = (tmp / 'out' / 'term_scores' / f'{TERM}.json').read_text().split('"updated"')[0]
    code, out = run(t1)
    after = (tmp / 'out' / 'term_scores' / f'{TERM}.json').read_text().split('"updated"')[0]
    check('re-running the same file changes nothing', code == 0 and before == after and 'fields applied 0' in out, out)

    t2 = hand('t2.json', 'Mr Bola', [edit(A, ca=22, ca_at='2026-10-29T10:00:00.000Z')])
    code, out = run(t2)
    check('a newer value from another phone wins and is reported as a conflict', record()[(A['id'], 'english')]['ca'] == 22 and 'CONFLICT' in out, out)

    t3 = hand('t3.json', 'Mrs Late', [edit(A, ca=5, ca_at='2026-10-29T08:00:00.000Z')])
    code, out = run(t3)
    check('an older value is ignored', record()[(A['id'], 'english')]['ca'] == 22 and 'ignored 5' in out, out)

    bad = hand('bad.json', 'Mr Tamper', [edit(B, ca=30, ca_at='2026-10-29T09:00:00.000Z')], tamper=True)
    code, out = run(bad)
    check('a damaged file is refused whole and flagged', code == 1 and 'CHECKSUM MISMATCH' in out and (B['id'], 'english') not in record(), out)

    mixed = hand('mixed.json', 'Mrs Mixed', [
        edit(B, ca=18, ca_at='2026-10-29T09:00:00.000Z'),
        {**edit(B, subject='physics'), 'student_name': 'Somebody Else', 'ca': 10, 'ca_at': '2026-10-29T09:00:00.000Z'},
        {**edit(B), 'student_id': 'TCH-1999-999', 'ca': 10, 'ca_at': '2026-10-29T09:00:00.000Z'},
        {**edit(B, subject='mathematics'), 'ca': 140, 'ca_at': '2026-10-29T09:00:00.000Z'},
    ])
    code, out = run(mixed)
    check('good entries in a file are kept', record()[(B['id'], 'english')]['ca'] == 18, out)
    check('id/name mismatch is rejected for a human', "id and name disagree" in out and (B['id'], 'physics') not in record(), out)
    check('unknown student is rejected', 'not on the active roster' in out, out)
    check('a score above 100 is rejected', 'not a number from 0 to 100' in out and (B['id'], 'mathematics') not in record(), out)

    n_reports = len(list((tmp / 'out' / 'reports').glob('*.txt')))
    n_applied = len(list((tmp / 'out' / 'applied').glob('*.json')))
    code, out = run(t1, dry=True)
    check('dry run reports but writes nothing',
          'dry run' in out and len(list((tmp / 'out' / 'reports').glob('*.txt'))) == n_reports
          and len(list((tmp / 'out' / 'applied').glob('*.json'))) == n_applied)

print(f'\n{passed} passed')

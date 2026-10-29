#!/usr/bin/env python3
"""
Merge teachers' "scores files" (sent from the teacher app's dashboard) into the
school's canonical score record.

    python3 scripts/scores/ingest.py FILE [FILE ...]            # apply
    python3 scripts/scores/ingest.py FILE ... --dry-run         # report only

Then publish the merged scores back to every device:

    python3 scripts/generate_teacher_data.py                     # bundles them
    (commit, deploy)                                             # no server watches for changes

What it does, in order, for each file:
  1. Checksum + format. A file that was cut short or altered in transit is
     REFUSED whole (nothing from it is applied) and reported.
  2. Entry by entry, against the canonical roster (scripts/roster/students.json)
     and the app's own subject list (src/lib/teacherData.ts):
       unknown student / unknown subject / unknown term   -> entry rejected
       student id exists but the NAME differs             -> entry rejected
                                      (an id drifting from its person must be
                                       checked by a human, never merged)
       score not a number in 0..100                       -> entry rejected
       student now sits in a different class than the file says, or the class
       does not study that subject                        -> accepted, WARNED
  3. Merge per field (CA and Exam separately): the most recently typed value
     wins (each field carries the time it was typed). Same field typed on two
     different phones with different values is listed as a CONFLICT for
     a human to look at -- the newer one is applied, the other is in the report.

Re-running the same file changes nothing (idempotent). Inputs are archived in
scripts/scores/applied/; a dated report is written to scripts/scores/reports/.
Canonical output: scripts/scores/term_scores/<term_id>.json
Exit status is 1 if any file was refused, so a script can notice.
"""
import argparse, hashlib, json, os, re, shutil, sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# TENDERCARE_SCORES_DIR redirects all output (tests use this); reference data is always the repo's.
BASE = Path(os.environ.get('TENDERCARE_SCORES_DIR') or ROOT / 'scripts' / 'scores')
OUT_DIR = BASE / 'term_scores'
APPLIED = BASE / 'applied'
REPORTS = BASE / 'reports'
FORMAT, VERSION = 'tendercare-scores', 1


def ts_array(text: str, name: str):
    """A JSON array from the generated teacherData.ts: either `= [...];` or `= ([...] as ...).map(`."""
    m = re.search(r'export const %s\b[^=]*= \(?(\[.*?\])(?:;\n| as )' % name, text, re.S)
    if not m:
        sys.exit(f'could not find `{name}` in src/lib/teacherData.ts -- has the generator output changed?')
    return json.loads(m.group(1))


def load_reference():
    roster = json.loads((ROOT / 'scripts/roster/students.json').read_text())['students']
    students = {s['id']: s for s in roster if s['status'] == 'active'}
    td = (ROOT / 'src/lib/teacherData.ts').read_text()
    subjects = {s['id']: s['name'] for s in ts_array(td, 'subjects')}
    links = {(c, sj) for c, sj in ts_array(td, 'classSubjects')}
    terms = {t['id'] for t in ts_array(td, 'terms')}
    return students, subjects, links, terms


def js_checksum(edits) -> str:
    # Matches the app: SHA-256 of JSON.stringify(edits) -- compact, no ASCII escaping.
    return hashlib.sha256(json.dumps(edits, ensure_ascii=False, separators=(',', ':')).encode('utf-8')).hexdigest()


def norm(name: str) -> str:
    return re.sub(r'\s+', ' ', (name or '').strip().lower())


def load_term(term_id: str) -> dict:
    f = OUT_DIR / f'{term_id}.json'
    if f.exists():
        return json.loads(f.read_text())
    return {'term_id': term_id, 'rows': []}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('files', nargs='+', type=Path)
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    students, subjects, links, terms = load_reference()
    store: dict[str, dict] = {}                     # term_id -> term document
    index: dict[tuple, dict] = {}                   # (term, student, subject) -> row
    log: list[str] = []
    refused: list[str] = []
    tally = {'files': 0, 'applied': 0, 'unchanged': 0, 'older': 0, 'rejected': 0, 'warned': 0, 'conflicts': 0}

    def row_for(term_id, stu, subj):
        k = (term_id, stu, subj)
        if k not in index:
            doc = store.setdefault(term_id, load_term(term_id))
            for r in doc['rows']:
                index[(term_id, r['student_id'], r['subject_id'])] = r
            if k not in index:
                r = {'student_id': stu, 'subject_id': subj, 'ca': None, 'exam': None}
                doc['rows'].append(r)
                index[k] = r
        return index[k]

    for path in a.files:
        label = path.name
        try:
            hand = json.loads(path.read_text())
        except Exception as e:
            refused.append(f'{label}: not readable JSON ({e})'); continue
        if hand.get('format') != FORMAT or hand.get('version') != VERSION or not isinstance(hand.get('edits'), list):
            refused.append(f'{label}: not a Tendercare scores file (format/version)'); continue
        if js_checksum(hand['edits']) != hand.get('checksum'):
            refused.append(f'{label}: CHECKSUM MISMATCH -- damaged or altered after it was made; ask for it to be sent again'); continue

        tally['files'] += 1
        who = (hand.get('teacher') or {}).get('name') or 'unnamed teacher'
        device = str(hand.get('device', ''))[:8]
        src = f'{who} / device {device} / {label}'
        log.append(f'== {label}  ({who}, {len(hand["edits"])} entries, exported {hand.get("exportedAt")})')

        for e in hand['edits']:
            sid, sub, term = e.get('student_id'), e.get('subject_id'), e.get('term_id')
            tag = f'{sid} {e.get("student_name", "")!r} / {e.get("subject_name", sub)} / {term}'
            st = students.get(sid)
            if st is None:
                log.append(f'  REJECT  {tag}: student not on the active roster'); tally['rejected'] += 1; continue
            if sub not in subjects:
                log.append(f'  REJECT  {tag}: unknown subject id'); tally['rejected'] += 1; continue
            if term not in terms:
                log.append(f'  REJECT  {tag}: unknown term'); tally['rejected'] += 1; continue
            if e.get('student_name') and norm(e['student_name']) != norm(st['full_name']):
                log.append(f'  REJECT  {tag}: roster says {st["full_name"]!r} -- id and name disagree, needs a human'); tally['rejected'] += 1; continue
            warned = False
            if e.get('class_id') and e['class_id'] != st['class_id']:
                log.append(f'  WARN    {tag}: file says class {e["class_id"]}, roster says {st["class_id"]} (moved?)'); warned = True
            if (st['class_id'], sub) not in links:
                log.append(f'  WARN    {tag}: {st["class_id"]} has no {subjects[sub]} in its subject list'); warned = True
            tally['warned'] += warned

            for f in ('ca', 'exam'):
                if f not in e:
                    continue
                v, at = e[f], e.get(f'{f}_at', '') or ''
                if v is not None and not (isinstance(v, (int, float)) and not isinstance(v, bool) and 0 <= v <= 100):
                    log.append(f'  REJECT  {tag}: {f.upper()} {v!r} is not a number from 0 to 100'); tally['rejected'] += 1; continue
                row = row_for(term, sid, sub)
                cur_at, cur_v = row.get(f'{f}_at'), row[f]
                if cur_at is not None and (cur_at, ) >= (at, ):
                    if cur_v == v:
                        tally['unchanged'] += 1
                    else:
                        tally['older'] += 1
                        if cur_at != at:
                            log.append(f'  CONFLICT {tag} {f.upper()}: kept {cur_v} (typed {cur_at}), ignored {v} (typed {at or "unknown"}) from {src}'); tally['conflicts'] += 1
                    continue
                if cur_at is not None and cur_v != v:
                    log.append(f'  CONFLICT {tag} {f.upper()}: {v} (typed {at or "unknown"}) replaces {cur_v} (typed {cur_at}); was from {row.get(f"{f}_src")}'); tally['conflicts'] += 1
                row[f], row[f'{f}_at'], row[f'{f}_src'] = v, at, src
                tally['applied'] += 1

    stamp = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')
    summary = [f'scores ingest {stamp}', f'files accepted {tally["files"]}, refused {len(refused)}',
               f'fields applied {tally["applied"]}, already present {tally["unchanged"]}, older/ignored {tally["older"]}',
               f'entries rejected {tally["rejected"]}, warnings {tally["warned"]}, conflicts {tally["conflicts"]}']
    if refused:
        summary += ['', 'REFUSED FILES (nothing from these was applied):'] + [f'  {r}' for r in refused]
    report = '\n'.join(summary + [''] + log) + '\n'
    print(report)

    if a.dry_run:
        print('(dry run -- nothing written)')
    else:
        OUT_DIR.mkdir(parents=True, exist_ok=True); APPLIED.mkdir(parents=True, exist_ok=True); REPORTS.mkdir(parents=True, exist_ok=True)
        for term_id, doc in store.items():
            doc['rows'].sort(key=lambda r: (r['subject_id'], r['student_id']))
            doc['updated'] = datetime.now(timezone.utc).isoformat(timespec='seconds')
            (OUT_DIR / f'{term_id}.json').write_text(json.dumps(doc, indent=1, ensure_ascii=False) + '\n')
        for p in a.files:
            if p.exists():
                shutil.copy2(p, APPLIED / p.name)
        (REPORTS / f'ingest-{stamp}.txt').write_text(report)
    sys.exit(1 if refused else 0)


if __name__ == '__main__':
    main()

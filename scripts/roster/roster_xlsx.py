#!/usr/bin/env python3
"""Downloadable roster workbook from the canonical roster (needs openpyxl).

    python3 scripts/roster/roster_xlsx.py [--since 2026-11-11] [--out roster.xlsx]

Two sheets: "All students" (every active student, by class) and
"Added since <date>". Same data as roster_html.py. Reads only.
"""
import argparse, datetime, importlib.util, json, pathlib

from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill

HERE = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location('roster_html', HERE / 'roster_html.py')
rh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rh)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--since', default='2026-11-11')
    ap.add_argument('--out', default='tendercare-roster.xlsx')
    a = ap.parse_args()

    doc = json.loads((HERE / 'students.json').read_text())
    adds = rh.added_dates()
    rows = []
    for s in doc['students']:
        if s['status'] != 'active':
            continue
        added = rh.added_for(s, adds)
        rows.append([s['id'], s['full_name'], rh.LABEL.get(s['class_id'], s['class_id']),
                     rh.ADMISSION.get(s.get('admission_type'), s.get('admission_type')),
                     datetime.date.fromisoformat(added) if added > a.since else None,
                     '; '.join(f['name'] for f in s.get('former_names', [])) or None])
    unlabel = {v: k for k, v in rh.LABEL.items()}
    rows.sort(key=lambda r: (rh.ORDER.index(unlabel.get(r[2], r[2])), r[1].lower()))
    new = sorted((r[:5] for r in rows if r[4]), key=lambda r: r[0])

    wb = Workbook()

    def put(ws, head, rs, widths):
        ws.append(head)
        for r in rs:
            ws.append(r)
        for c in ws[1]:
            c.fill = PatternFill('solid', fgColor='F3F3F3')
            c.font = Font(bold=True)
        for row in ws.iter_rows(min_row=2):
            for c in row:
                if isinstance(c.value, datetime.date):
                    c.number_format = 'd mmm yyyy'
        for col, w in widths.items():
            ws.column_dimensions[col].width = w
        ws.freeze_panes = 'A2'

    ws = wb.active
    ws.title = 'All students'
    put(ws, ['ID', 'Name', 'Class', 'Admission', 'Added on', 'Former name'], rows,
        {'A': 15, 'B': 30, 'C': 15, 'D': 21, 'E': 13, 'F': 24})
    label = datetime.date.fromisoformat(a.since).strftime('%-d %b')
    put(wb.create_sheet(f'Added since {label}'), ['ID', 'Name', 'Class', 'Admission', 'Added on'], new,
        {'A': 15, 'B': 30, 'C': 15, 'D': 21, 'E': 13})
    wb.save(a.out)
    print(f'{a.out}: {len(rows)} students, {len(new)} added since {a.since}')


if __name__ == '__main__':
    main()

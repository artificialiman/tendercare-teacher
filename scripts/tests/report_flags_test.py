#!/usr/bin/env python3
"""Run:  python3 scripts/tests/report_flags_test.py
Marks limits (Junior CA 40 + Exam 60, Senior CA 30 + Exam 70), the
[confirm with your teacher] flag, and the class-at-the-time publish gate."""
import copy, json, sys
from pathlib import Path

PIPE = Path(__file__).resolve().parents[1] / 'report-pipeline'
sys.path.insert(0, str(PIPE))
import generate as g          # noqa: E402
import compute_awards as aw   # noqa: E402

BASE = json.loads((PIPE / 'students' / 'TCH-0000-001.json').read_text())
passed = 0


def check(name, cond, detail=''):
    global passed
    assert cond, f'{name}: {detail}'
    passed += 1
    print('  ok  ', name)


def student(class_at_time, subjects, sid='TCH-9999-001', class_arm=None):
    d = copy.deepcopy(BASE)
    d['student_id'], d['class_arm'] = sid, class_arm or class_at_time
    y = d['years'][-1]
    y['class_at_time'] = class_at_time
    t = y['terms'][-1]
    t['digitized'], t['subjects'] = True, [dict(name=f'S{i}', ca=c, exam=e) for i, (c, e) in enumerate(subjects)]
    return d


def term_of(d):
    stats = g.compute_gate_stats([d])
    warnings = []
    y = d['years'][-1]
    key = (y['class_at_time'], y['academic_year'], y['terms'][-1]['term_name'])
    return g.compute_term(y['terms'][-1], key, stats, warnings, y['class_at_time']), warnings


# --- the limits ---------------------------------------------------------
check('limits: JSS 40/60, SS 30/70, legacy JS1 is junior, others unknown',
      g.marks_limits_for('JSS2A') == (40, 60) and g.marks_limits_for('JS1') == (40, 60)
      and g.marks_limits_for('SS1 Science') == (30, 70) and g.marks_limits_for('Form 4') is None
      and g.marks_limits_for(None) is None)

t, _ = term_of(student('JSS1A', [(40, 60), (41, 50), (30, 61), (-1, 50), ('30', 50), (True, 50)]))
sub = t['subjects']
check('junior: 40+60 is fine, graded 100', sub[0]['total'] == 100 and not sub[0]['flag'])
check('junior: CA 41 is flagged', sub[1]['flag'] and sub[1]['ca_flag'] and not sub[1]['exam_flag'])
check('junior: Exam 61 is flagged', sub[2]['flag'] and sub[2]['exam_flag'] and not sub[2]['ca_flag'])
check('negative and non-number and boolean are flagged', sub[3]['flag'] and sub[4]['flag'] and sub[5]['flag'])
check('flagged rows have no total or grade', all(s['total'] is None and s['grade'] is None for s in sub[1:]))
check('flagged subjects are left out of total, max and average',
      t['total_score'] == 100 and t['max_score'] == 100 and t['average'] == 100 and t['flagged_count'] == 5)

t, _ = term_of(student('SS2 Science', [(30, 70), (31, 60), (20, 71), (25, 60)]))
sub = t['subjects']
check('senior: 30+70 fine; CA 31 and Exam 71 flagged; 25+60 graded',
      sub[0]['total'] == 100 and sub[1]['flag'] and sub[2]['flag'] and sub[3]['total'] == 85)
check('senior average counts only unflagged subjects', t['average'] == 92.5 and t['max_score'] == 200)

t, _ = term_of(student('Form 4', [(20, 50)]))
check('unknown class: nothing can be trusted, everything entered is flagged',
      t['subjects'][0]['flag'] and t['flagged_count'] == 1 and t['limits_text'] is None)

half = student('JSS1A', [(30, None), (45, None), (None, None)])
mate = student('JSS1A', [(20, 50)], sid='TCH-9999-002')   # a completed classmate clears the 40% gate
y = half['years'][-1]
t, _ = (g.compute_term(y['terms'][-1], ('JSS1A', y['academic_year'], y['terms'][-1]['term_name']),
                       g.compute_gate_stats([half, mate]), [], 'JSS1A'), None)
check('a valid half-entry is pending, an invalid half-entry is flagged, empty is neither',
      not t['subjects'][0]['flag'] and t['subjects'][1]['flag'] and not t['subjects'][2]['flag'])

# --- what is printed ----------------------------------------------------
html = g.render_student(student('SS1 Science', [(35, 50), (20, 60)]), g.compute_gate_stats([student('SS1 Science', [(35, 50), (20, 60)])]), [])
check('flag text and the explanation are on the report sheet',
      html.count('[confirm with your teacher]') >= 2 and 'not graded and not included in the total or average' in html
      and 'CA 30 + Exam 70' in html)
html_ok = g.render_student(student('SS1 Science', [(20, 60)]), g.compute_gate_stats([student('SS1 Science', [(20, 60)])]), [])
check('a normal report has no flag', 'confirm with your teacher]' not in html_ok.split('</style>')[-1])

# --- awards follow the same rule -----------------------------------------
d = student('SS1 Science', [(35, 50), (20, 60)])
avg = aw.student_average_for_term(d, d['years'][-1]['academic_year'], d['years'][-1]['terms'][-1]['term_name'])
check('awards ranking ignores a flagged subject', avg == 80.0, avg)

# --- the publish gate counts the class AT THE TIME, not today's class ------
old = student('JSS1B', [(30, 50)], sid='TCH-9999-010')
intake = []
for i in range(29):
    n = copy.deepcopy(BASE)
    n['student_id'], n['class_arm'] = f'TCH-9999-{100+i}', 'JSS1B'
    n['years'] = [dict(academic_year='2026/2027', class_at_time='JSS1B', is_current=True,
                       terms=[dict(term_name=x, digitized=False) for x in ('First', 'Second', 'Third')])]
    intake.append(n)
old['class_arm'] = 'JSS2B'  # promoted since; last year's term must not be judged against today's class
stats = g.compute_gate_stats([old] + intake)
y = old['years'][-1]
s = stats[('JSS1B', y['academic_year'], 'Third')]
check('new intake in the same class does not block last year\'s published term',
      s['total'] == 1 and s['pct'] == 1.0, s)

print(f'\n{passed} passed')

#!/usr/bin/env python3
"""Printable, offline roster page from the canonical roster.

    python3 scripts/roster/roster_html.py [--since 2026-11-11] [--out roster.html]

One self-contained HTML file (no network): the students added after --since at
the top, then every active student grouped by class, with a search box.
Added dates come from scripts/roster/applied/; former spellings from
students.json. Reads only -- changes nothing.
"""
import argparse, collections, datetime, html, json, pathlib

HERE = pathlib.Path(__file__).resolve().parent
ORDER = ['JSS1A', 'JSS1B', 'JSS2A', 'JSS2B', 'JSS3A', 'JSS3B', 'SS1 Unassigned', 'SS1 Science',
         'SS1 Actuarial', 'SS2 Science', 'SS2 Actuarial', 'SS3 Science', 'SS3 Actuarial']
LABEL = {'SS1 Unassigned': 'SS1 New'}
ADMISSION = {None: 'Continuing', '': 'Continuing', 'intake': 'JSS1 intake 2026/27', 'transfer_in': 'Transfer-in 2026/27'}


def added_dates() -> dict:
    """(full_name, class_id) of each add -> date of the change file that added it."""
    out = {}
    for f in sorted((HERE / 'applied').glob('*.json')):
        for c in json.loads(f.read_text()).get('changes', []):
            if c.get('action') == 'add':
                out[(c['full_name'], c['class_id'])] = f.name[:10]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--since', default='2026-11-11', help='list students added after this date at the top')
    ap.add_argument('--out', default='tendercare-roster.html')
    a = ap.parse_args()

    doc = json.loads((HERE / 'students.json').read_text())
    adds = added_dates()
    rows = []
    for s in doc['students']:
        if s['status'] != 'active':
            continue
        added = adds.get((s['full_name'], s['class_id']), '')
        # A student moved after being added keeps the add date of the class they were added to.
        if not added:
            added = next((d for (n, c), d in adds.items() if n == s['full_name']), '')
        rows.append(dict(id=s['id'], name=s['full_name'], cls=s['class_id'],
                         adm=ADMISSION.get(s.get('admission_type'), s.get('admission_type')),
                         added=added if added > a.since else '',
                         former='; '.join(f['name'] for f in s.get('former_names', []))))
    rows.sort(key=lambda r: (ORDER.index(r['cls']) if r['cls'] in ORDER else 99, r['name'].lower()))
    new = sorted((r for r in rows if r['added']), key=lambda r: r['id'])

    e = html.escape
    day = lambda v: datetime.date.fromisoformat(v).strftime('%-d %b %Y') if v else ''
    groups = collections.OrderedDict()
    for r in rows:
        groups.setdefault(LABEL.get(r['cls'], r['cls']), []).append(r)
    nav = ' '.join(f'<a href="#c{i}">{e(c)} <span>{len(v)}</span></a>' for i, (c, v) in enumerate(groups.items()))
    sections = []
    for i, (c, rs) in enumerate(groups.items()):
        tr = ''.join(f'<tr{" class=new" if r["added"] else ""}><td>{n}</td><td class=id>{e(r["id"])}</td>'
                     f'<td>{e(r["name"])}</td><td>{e(r["adm"])}</td><td>{day(r["added"])}</td><td>{e(r["former"])}</td></tr>'
                     for n, r in enumerate(rs, 1))
        sections.append(f'<section id="c{i}"><h3>{e(c)} <span>{len(rs)} students</span></h3><table><thead><tr><th>#</th>'
                        f'<th>ID</th><th>Name</th><th>Admission</th><th>Added on</th><th>Former name</th></tr></thead><tbody>{tr}</tbody></table></section>')
    newtr = ''.join(f'<tr><td>{n}</td><td class=id>{e(r["id"])}</td><td>{e(r["name"])}</td><td>{e(LABEL.get(r["cls"], r["cls"]))}</td>'
                    f'<td>{e(r["adm"])}</td><td>{day(r["added"])}</td></tr>' for n, r in enumerate(new, 1))
    bydate = collections.Counter(r['added'] for r in new)
    since = day(a.since)
    today = datetime.date.today().strftime('%-d %B %Y')
    page = f'''<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Tendercare Comprehensive College: Student roster {e(doc.get("session", ""))}</title>
<style>
:root{{--cream:#faf6ec;--purple:#4b2a6b;--green:#2f6b3f;--line:#e4dccb}}
*{{box-sizing:border-box}}body{{margin:0;font:14px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;background:var(--cream);color:#222}}
header{{background:var(--purple);color:#fff;padding:18px 20px}}header h1{{margin:0;font-size:20px}}header p{{margin:4px 0 0;opacity:.85}}
main{{max-width:980px;margin:0 auto;padding:16px}}
h2{{color:var(--purple);border-bottom:3px solid var(--green);padding-bottom:4px;margin:28px 0 10px}}
h3{{color:var(--green);margin:22px 0 6px}}h3 span,nav span{{color:#777;font-weight:normal;font-size:13px}}
nav{{display:flex;flex-wrap:wrap;gap:6px;margin:10px 0}}nav a{{background:#fff;border:1px solid var(--line);border-radius:14px;padding:3px 10px;color:var(--purple);text-decoration:none}}
.summary{{display:flex;flex-wrap:wrap;gap:10px}}.summary div{{background:#fff;border:1px solid var(--line);border-radius:8px;padding:8px 12px}}.summary b{{display:block;font-size:20px;color:var(--purple)}}
table{{width:100%;border-collapse:collapse;background:#fff}}th,td{{padding:5px 8px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}}
th{{background:#efe8d8;font-weight:600;position:sticky;top:0}}td:first-child,th:first-child{{width:36px;color:#888}}td.id{{font-family:ui-monospace,Menlo,Consolas,monospace;white-space:nowrap}}
tr.new td{{background:#eef6ef}}input{{width:100%;padding:8px 10px;border:1px solid var(--line);border-radius:6px;font:inherit;margin:6px 0 2px}}
.note{{color:#666;font-size:13px}}
@media print{{header{{background:none;color:#000;padding:0}}nav,input,.noprint{{display:none}}th{{position:static}}h3{{break-after:avoid}}body{{background:#fff}}}}
</style></head><body>
<header><h1>Tendercare Comprehensive College: Student roster</h1><p>{e(doc.get("session", ""))} session. {len(rows)} active students. Generated {today} from the canonical roster.</p></header>
<main>
<h2>Students added since {since}</h2>
<div class="summary"><div><b>{len(new)}</b>added</div>{"".join(f"<div><b>{n}</b>{day(k)}</div>" for k, n in sorted(bydate.items()))}</div>
<p class="note">These rows are also shaded green in the class lists below.</p>
<table><thead><tr><th>#</th><th>ID</th><th>Name</th><th>Class</th><th>Admission</th><th>Added on</th></tr></thead><tbody>{newtr}</tbody></table>
<h2>All students by class</h2>
<input class="noprint" id="q" placeholder="Search by name or ID" oninput="f(this.value)">
<nav>{nav}</nav>
{"".join(sections)}
<p class="note">SS1 New: students still waiting for an SS1 department. "Former name": the spelling replaced by a correction; the student keeps the same ID.</p>
</main>
<script>
function f(v){{v=v.toLowerCase();document.querySelectorAll('section').forEach(function(s){{var n=0;s.querySelectorAll('tbody tr').forEach(function(r){{var h=r.textContent.toLowerCase().indexOf(v)<0;r.style.display=h?'none':'';if(!h)n++}});s.style.display=n?'':'none'}})}}
</script>
</body></html>'''
    pathlib.Path(a.out).write_text(page, encoding='utf-8')
    print(f'{a.out}: {len(rows)} students, {len(new)} added since {a.since}')


if __name__ == '__main__':
    main()

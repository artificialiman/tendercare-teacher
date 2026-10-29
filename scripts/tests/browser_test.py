#!/usr/bin/env python3
"""
Real-browser tests of the offline behaviour. Needs Python Playwright with
Chromium:   pip install playwright && playwright install chromium

    npm run build
    python3 scripts/tests/browser_test.py

Starts `vite preview` itself. Covers: the app opening with no connection at
every address, the score sheet (saving, refusing bad values, blanks, offline
reload, full disk, clear-all), and the scores file (send, wipe, restore, merge,
tamper). Exit status 1 if anything fails.
"""
import json, os, signal, subprocess, sys, tempfile, time, urllib.request
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[2]
PORT = 4173
BASE = f'http://localhost:{PORT}'
SHEET = BASE + '/score/sheet?subject=english&class=JSS1A'
PROFILE = """localStorage.setItem('tc_teacher_profile', JSON.stringify({name:'Mrs Ada Obi', subjectIds:['english'], classIds:['JSS1A'], classTeacherIds:[]}))"""
fails: list[str] = []


def check(name, cond, extra=''):
    print(('  ok   ' if cond else '  FAIL ') + name + ('' if cond else f'  {extra}'))
    if not cond:
        fails.append(name)


def start_preview():
    p = subprocess.Popen(['npx', 'vite', 'preview', '--port', str(PORT), '--strictPort'], cwd=ROOT,
                         stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT, preexec_fn=os.setsid)
    for _ in range(60):
        try:
            urllib.request.urlopen(BASE + '/', timeout=1)
            return p
        except Exception:
            time.sleep(0.5)
    raise RuntimeError('preview did not start (did you run npm run build?)')


def setup_teacher(pg):
    pg.goto(BASE + '/')
    pg.wait_for_timeout(1500)
    pg.evaluate(PROFILE)


def test_offline_shell(b):
    print('offline shell')
    ctx = b.new_context(); pg = ctx.new_page(); errs = []
    pg.on('pageerror', lambda e: errs.append(str(e)[:120]))
    pg.goto(BASE + '/'); pg.wait_for_timeout(3500)
    check('service worker controls the page', pg.evaluate('!!navigator.serviceWorker.controller'))
    ctx.set_offline(True)
    for path in ['/', '/broadsheet', '/score', '/attendance', '/roster?class=JSS1A', '/score/sheet?subject=english&class=JSS1A']:
        try:
            pg.goto(BASE + path, wait_until='load', timeout=15000); pg.wait_for_timeout(500)
            check(f'offline load {path}', len(pg.inner_text('body')) > 20)
        except Exception as e:
            check(f'offline load {path}', False, str(e).splitlines()[0][:100])
    check('no page errors', not errs, errs)
    ctx.close()


def test_sheet(b):
    print('score sheet')
    ctx = b.new_context(); pg = ctx.new_page(); errs = []
    pg.on('pageerror', lambda e: errs.append(str(e)[:120]))
    setup_teacher(pg)
    edits = lambda: json.loads(pg.evaluate("localStorage.getItem('tc_score_edits')") or '{"edits":[]}')['edits']
    pg.goto(SHEET); pg.wait_for_selector('.score-input')
    inp = pg.locator('.score-input'); ca, ex = inp.nth(0), inp.nth(1)
    ca.fill('25'); ex.click(); pg.wait_for_timeout(300)
    check('typed CA saved to the device', len(edits()) == 1 and edits()[0].get('ca') == 25)
    check('status says saved on this device', 'Saved on this device' in pg.inner_text('body'))
    ca.fill('85'); ex.click(); pg.wait_for_timeout(300)
    check('over-max flagged, not clamped', pg.locator('.score-input.refused').count() >= 1 and ca.input_value() == '85')
    check('over-max not saved', edits()[0].get('ca') == 25)
    ca.fill('30'); ex.click(); pg.wait_for_timeout(300)
    check('corrected value saves, flag clears', edits()[0].get('ca') == 30 and pg.locator('.score-input.refused').count() == 0)
    ex.fill('50'); ca.click(); pg.wait_for_timeout(300)
    check('total = 80', '80' in pg.locator('tbody tr').nth(0).inner_text())
    ex.fill(''); ca.click(); pg.wait_for_timeout(300)
    check('blank saves as a real blank', 'exam' in edits()[0] and edits()[0]['exam'] is None)
    pg.locator('.max-input').nth(0).fill('40'); pg.wait_for_timeout(200)
    ctx.set_offline(True); pg.reload(); pg.wait_for_selector('.score-input')
    check('offline reload keeps the score', pg.locator('.score-input').nth(0).input_value() == '30')
    check('offline reload keeps the blank', pg.locator('.score-input').nth(1).input_value() == '')
    check('max marks remembered', pg.locator('.max-input').nth(0).input_value() == '40')
    pg.evaluate("""(()=>{const o=Storage.prototype.setItem; Storage.prototype.setItem=function(k,v){ if(k==='tc_score_edits'){const e=new Error('full'); e.name='QuotaExceededError'; throw e;} return o.call(this,k,v)}; return 1})()""")
    pg.locator('.score-input').nth(4).fill('15'); pg.locator('.score-input').nth(5).click(); pg.wait_for_timeout(300)
    check('full disk shows a clear warning', pg.locator('.save-state--bad').count() == 1)
    check('value stays on screen', pg.locator('.score-input').nth(4).input_value() == '15')
    pg.reload(); pg.wait_for_selector('.score-input')
    pg.on('dialog', lambda d: d.accept())
    pg.get_by_text('Clear all').click(); pg.wait_for_timeout(500)
    check('Clear all empties the sheet', all(pg.locator('.score-input').nth(i).input_value() == '' for i in range(6)))
    check('Clear all writes blanks, not zeros', not [e for e in edits() if e.get('ca') == 0 or e.get('exam') == 0])
    check('no page errors', not errs, errs)
    ctx.close()


def test_scores_file(b, tmp: Path):
    print('scores file')
    ctx = b.new_context(accept_downloads=True); pg = ctx.new_page(); errs = []
    pg.on('pageerror', lambda e: errs.append(str(e)[:120]))
    setup_teacher(pg)
    pg.goto(SHEET); pg.wait_for_selector('.score-input')
    for i, v in enumerate(['24', '61', '18', '55', '30', '70']):
        pg.locator('.score-input').nth(i).fill(v); pg.keyboard.press('Tab')
    pg.wait_for_timeout(400)
    pg.goto(BASE + '/'); pg.wait_for_selector('.device-card')
    txt = pg.inner_text('.device-card')
    check('card counts entries on this phone', '3 entries typed' in txt, txt[:200])
    check('card says nothing handed in yet', 'Not sent anywhere yet' in txt)
    with pg.expect_download() as dl:
        pg.get_by_text('Send scores file').click()
    f = tmp / 'sent.json'; dl.value.save_as(f)
    h = json.loads(f.read_text())
    check('file named for teacher and date', dl.value.suggested_filename.startswith('tendercare-scores-mrs-ada-obi-'))
    check('file has the right format and term', h['format'] == 'tendercare-scores' and h['termId'] == '2026-2027-T1')
    check('3 students, 6 fields, names beside ids', len(h['edits']) == 3 and all(e.get('student_name') for e in h['edits']))
    pg.wait_for_timeout(300)
    check('card shows last sent', 'nothing new since' in pg.inner_text('.device-card'))
    pg.evaluate('localStorage.clear()'); pg.reload(); pg.wait_for_timeout(600)
    pg.evaluate(PROFILE); pg.reload(); pg.wait_for_selector('.device-card')
    check('wiped phone has no scores', '0 entries typed' in pg.inner_text('.device-card'))
    pg.set_input_files('input[type=file]', str(f)); pg.wait_for_timeout(600)
    check('restore reports what it did', 'Restored 6 scores' in pg.inner_text('.device-card'))
    pg.goto(SHEET); pg.wait_for_selector('.score-input')
    check('restored scores on the sheet', [pg.locator('.score-input').nth(i).input_value() for i in range(6)] == ['24', '61', '18', '55', '30', '70'])
    pg.locator('.score-input').nth(0).fill('27'); pg.keyboard.press('Tab'); pg.wait_for_timeout(300)
    pg.goto(BASE + '/'); pg.wait_for_selector('.device-card')
    pg.set_input_files('input[type=file]', str(f)); pg.wait_for_timeout(600)
    pg.goto(SHEET); pg.wait_for_selector('.score-input')
    check('restoring an older file keeps newer typing', pg.locator('.score-input').nth(0).input_value() == '27')
    t = json.loads(f.read_text()); t['edits'][0]['ca'] = 99
    (tmp / 'tampered.json').write_text(json.dumps(t))
    pg.goto(BASE + '/'); pg.wait_for_selector('.device-card')
    pg.set_input_files('input[type=file]', str(tmp / 'tampered.json')); pg.wait_for_timeout(600)
    check('tampered file refused', 'damaged or incomplete' in pg.inner_text('.device-card'))
    (tmp / 'junk.json').write_text('hello')
    pg.set_input_files('input[type=file]', str(tmp / 'junk.json')); pg.wait_for_timeout(500)
    check('non-scores file refused', 'could not be read' in pg.inner_text('.device-card'))
    check('no page errors', not errs, errs)
    ctx.close()


def main():
    srv = start_preview()
    try:
        with sync_playwright() as p, tempfile.TemporaryDirectory() as d:
            b = p.chromium.launch()
            test_offline_shell(b); test_sheet(b); test_scores_file(b, Path(d))
            b.close()
    finally:
        try:
            os.killpg(os.getpgid(srv.pid), signal.SIGTERM)
        except Exception:
            pass
    print('\nFAILED: ' + ', '.join(fails) if fails else '\nALL PASSED')
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()

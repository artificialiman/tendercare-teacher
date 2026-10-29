// Run:  npx tsx scripts/tests/local_state_test.mts
// Exercises src/lib/localState.ts against a fake browser storage that can
// fill up, silently drop writes, or hold corrupt data. No browser needed.
import assert from 'node:assert/strict';

class FakeStorage {
	data = new Map<string, string>();
	mode: 'ok' | 'quota' | 'drop' = 'ok';
	getItem(k: string) { return this.data.has(k) ? this.data.get(k)! : null; }
	setItem(k: string, v: string) {
		if (this.mode === 'quota') { const e: any = new Error('full'); e.name = 'QuotaExceededError'; throw e; }
		if (this.mode === 'drop') return;
		this.data.set(k, String(v));
	}
	removeItem(k: string) { this.data.delete(k); }
}

const td = await import('../../src/lib/teacherData.ts');
let n = 0;
async function fresh(storage: FakeStorage) {
	(globalThis as any).localStorage = storage;
	td.scores.length = 0; td.remarks.length = 0;
	return await import(`../../src/lib/localState.ts?run=${++n}`);
}
const get = (st: any) => { let v: any; st.saveStatus.subscribe((x: any) => (v = x))(); return v; };
const T = td.currentTerm.id;
const ch = (field: 'ca' | 'exam', value: number | null, stu = 'S1', sub = 'SUB1') =>
	({ student_id: stu, subject_id: sub, term_id: T, field, value }) as const;
let passed = 0;
const test = async (name: string, fn: () => Promise<void>) => { await fn(); passed++; console.log('  ok  ', name); };

await test('a typed score is in memory and on the device, and reported as saved', async () => {
	const ls = new FakeStorage(); const st = await fresh(ls);
	const s = st.recordScoreChanges([ch('ca', 25)]);
	assert.equal(s.ok, true); assert.equal(s.scoreCells, 1);
	assert.deepEqual(td.scores.find((r) => r.student_id === 'S1'), { student_id: 'S1', subject_id: 'SUB1', term_id: T, ca: 25, exam: null });
	assert.ok(ls.getItem('tc_score_edits'));
});

await test('clearing a cell is saved as an explicit blank, and survives a reload', async () => {
	const ls = new FakeStorage(); let st = await fresh(ls);
	st.recordScoreChanges([ch('ca', 20), ch('exam', 50)]);
	st.recordScoreChanges([ch('ca', null)]);
	st = await fresh(ls);
	const row = td.scores.find((r) => r.student_id === 'S1')!;
	assert.equal(row.ca, null); assert.equal(row.exam, 50);
});

await test('reload restores every typed score on top of the baseline', async () => {
	const ls = new FakeStorage(); let st = await fresh(ls);
	st.recordScoreChanges([ch('ca', 11, 'A'), ch('exam', 22, 'A'), ch('ca', 33, 'B')]);
	st = await fresh(ls);
	assert.equal(td.scores.length, 2); assert.equal(get(st).scoreCells, 2);
});

await test('storage full: reported as failed, app still correct in memory', async () => {
	const ls = new FakeStorage(); const st = await fresh(ls);
	ls.mode = 'quota';
	const s = st.recordScoreChanges([ch('ca', 30)]);
	assert.equal(s.ok, false); assert.match(s.error, /out of storage/);
	assert.equal(td.scores.find((r) => r.student_id === 'S1')!.ca, 30);
	ls.mode = 'ok';
	assert.equal(st.recordScoreChanges([ch('exam', 40)]).ok, true, 'recovers on the next save');
});

await test('a write the browser silently dropped is caught by the read-back', async () => {
	const ls = new FakeStorage(); const st = await fresh(ls);
	ls.mode = 'drop';
	const s = st.recordScoreChanges([ch('ca', 30)]);
	assert.equal(s.ok, false); assert.match(s.error, /did not keep/);
});

await test('unreadable current record falls back to the previous generation', async () => {
	const ls = new FakeStorage(); let st = await fresh(ls);
	st.recordScoreChanges([ch('ca', 10)]);
	st.recordScoreChanges([ch('ca', 12)]); // now _bak holds the 10 version
	ls.data.set('tc_score_edits', '{"v":1,"edits":[ broken');
	st = await fresh(ls);
	assert.equal(td.scores.find((r) => r.student_id === 'S1')!.ca, 10);
	assert.ok(ls.getItem('tc_score_edits_corrupt'), 'broken copy kept for recovery');
});

await test('both generations unreadable: app opens, broken data is kept, later saves do not destroy it', async () => {
	const ls = new FakeStorage(); let st = await fresh(ls);
	ls.data.set('tc_score_edits', 'garbage1'); ls.data.set('tc_score_edits_bak', 'garbage2');
	st = await fresh(ls);
	assert.equal(td.scores.length, 0);
	st.recordScoreChanges([ch('ca', 5)]);
	assert.equal(ls.getItem('tc_score_edits_corrupt'), 'garbage1');
});

await test('merge: newest typed value wins per field; nothing is ever removed', async () => {
	const ls = new FakeStorage(); const st = await fresh(ls);
	st.recordScoreChanges([ch('ca', 10)], '2026-10-29T10:00:00.000Z');
	st.recordScoreChanges([ch('exam', 40)], '2026-10-29T11:00:00.000Z');
	const r = st.mergeScoreEdits([
		{ student_id: 'S1', subject_id: 'SUB1', term_id: T, ca: 99, ca_at: '2026-10-29T09:00:00.000Z', exam: 60, exam_at: '2026-10-29T12:00:00.000Z' },
		{ student_id: 'S2', subject_id: 'SUB1', term_id: T, ca: 7, ca_at: '2026-10-29T08:00:00.000Z' },
		{ nonsense: true }, { student_id: 'S3', subject_id: 'X', term_id: T, ca: 'abc' }
	]);
	assert.deepEqual([r.applied, r.keptNewer, r.invalid], [2, 1, 2]);
	const s1 = td.scores.find((x) => x.student_id === 'S1')!;
	assert.equal(s1.ca, 10, 'older incoming CA ignored'); assert.equal(s1.exam, 60, 'newer incoming exam taken');
	assert.equal(td.scores.find((x) => x.student_id === 'S2')!.ca, 7);
});

await test('upgrade from the old whole-table format keeps what was typed', async () => {
	const ls = new FakeStorage();
	ls.data.set('tc_local_state', JSON.stringify({ version: td.DATA_VERSION, scores: [{ student_id: 'S9', subject_id: 'SUB1', term_id: T, ca: 18, exam: null }] }));
	const st = await fresh(ls);
	assert.equal(td.scores.find((r) => r.student_id === 'S9')!.ca, 18);
	assert.ok(JSON.parse(ls.getItem('tc_score_edits')!).edits.length === 1);
	assert.equal(JSON.parse(ls.getItem('tc_local_state')!).scores, undefined, 'old table no longer duplicated');
});

await test('a rebuilt baseline drops roster edits but keeps every typed score', async () => {
	const ls = new FakeStorage(); let st = await fresh(ls);
	st.recordScoreChanges([ch('ca', 14)]);
	ls.data.set('tc_local_state', JSON.stringify({ version: 'old-version', students: [{ id: 'X' }], remarks: [] }));
	const before = td.students.length;
	st = await fresh(ls);
	assert.equal(td.students.length, before, 'roster edits from another baseline ignored');
	assert.equal(td.scores.find((r) => r.student_id === 'S1')!.ca, 14);
});

console.log(`\n${passed} passed`);

// ============================================================================
// On-device persistence for the hardcoded data. Nothing here touches a
// network: teacherData.ts is the baseline that ships with the app, and what a
// teacher changes on top of it is saved in this browser so a reload keeps it.
//
// Two separate records, on purpose:
//
//   tc_local_state   roster/class/remark changes (students added, moved,
//                    arms created). Tied to the baseline it was made on, so it
//                    is dropped when the baseline is regenerated (DATA_VERSION).
//
//   tc_score_edits   every score a teacher has typed: ONE small list of
//                    {student, subject, term, ca?, exam?, ca_at?, exam_at?}.
//                    Independent of DATA_VERSION -- scores are keyed by
//                    student/subject/term, so they stay valid across rebuilds.
//                    Each field carries its own timestamp, which is what lets
//                    the same sheet typed on two devices be merged correctly
//                    (newest typed value wins, per field) later on.
//
// Scores are NOT stored as a second copy of the whole score table: the saved
// record is only the edits, laid over whatever the shipped baseline contains.
// So a corrected baseline reaches every device, and only a teacher's own
// typing is ever in the saved record (small, exportable, mergeable).
//
// Safety, because this is the only copy until a backup is handed in:
//   * every save is read back and compared; a write the browser silently
//     dropped is reported as a failure, not assumed to have worked
//   * the previous version of each record is kept (…_bak) and used if the
//     current one is unreadable
//   * an unreadable record is moved aside (…_corrupt), never overwritten
//   * the browser is asked to treat this storage as persistent (not cleared
//     under space pressure)
//   * the app can show the outcome (saveStatus) -- a failed save is visible
// ============================================================================

import { writable } from 'svelte/store';
import { DATA_VERSION, students, classes, classSubjects, scores, remarks, type ScoreRecord } from './teacherData';

const KEY = 'tc_local_state';
const EDITS = 'tc_score_edits';

export interface ScoreEdit {
	student_id: string;
	subject_id: string;
	term_id: string;
	ca?: number | null;
	exam?: number | null;
	/** ISO time each field was last typed on some device. */
	ca_at?: string;
	exam_at?: string;
}

export interface SaveStatus {
	/** False once any save has failed this session, until a later save succeeds. */
	ok: boolean;
	lastSavedAt: string | null;
	error: string | null;
	/** Whether the browser agreed to keep this storage; null = unknown/unsupported. */
	persistent: boolean | null;
	/** Number of score cells this device holds typed values for. */
	scoreCells: number;
}

export const saveStatus = writable<SaveStatus>({
	ok: true,
	lastSavedAt: null,
	error: null,
	persistent: null,
	scoreCells: 0
});

function patchStatus(p: Partial<SaveStatus>): void {
	saveStatus.update((s) => ({ ...s, ...p }));
}

const hasStorage = (): boolean => {
	try {
		return typeof localStorage !== 'undefined';
	} catch {
		return false; // access itself can throw when storage is blocked
	}
};

function replaceContents<T>(target: T[], next: T[]): void {
	target.splice(0, target.length, ...next);
}

// ---------------------------------------------------------------------------
// Reading with fallbacks: current -> previous generation. An unreadable record
// is preserved under …_corrupt so a human can still recover it.
// ---------------------------------------------------------------------------

function readRecord(key: string): any | null {
	for (const k of [key, `${key}_bak`]) {
		let raw: string | null = null;
		try {
			raw = localStorage.getItem(k);
		} catch {
			return null;
		}
		if (!raw) continue;
		try {
			return JSON.parse(raw);
		} catch {
			try {
				if (!localStorage.getItem(`${key}_corrupt`)) localStorage.setItem(`${key}_corrupt`, raw);
			} catch {
				/* nothing more can be done */
			}
		}
	}
	return null;
}

/** Writes `value`, keeping the previous generation, and confirms it by reading it back. */
function writeRecord(key: string, value: unknown): void {
	const json = JSON.stringify(value);
	const previous = localStorage.getItem(key);
	if (previous) {
		try {
			localStorage.setItem(`${key}_bak`, previous);
		} catch {
			// A failed backup copy must not stop the real write from being tried.
		}
	}
	localStorage.setItem(key, json);
	if (localStorage.getItem(key) !== json) throw new Error('The browser did not keep the saved data');
}

// ---------------------------------------------------------------------------
// Score edits
// ---------------------------------------------------------------------------

const editKey = (student: string, subject: string, term: string) => `${student}|${subject}|${term}`;

const edits = new Map<string, ScoreEdit>();
let scoreIndex = new Map<string, ScoreRecord>();

function reindexScores(): void {
	scoreIndex = new Map(scores.map((r) => [editKey(r.student_id, r.subject_id, r.term_id), r]));
}

function applyEditToScores(e: ScoreEdit): void {
	const k = editKey(e.student_id, e.subject_id, e.term_id);
	let row = scoreIndex.get(k);
	if (!row) {
		row = { student_id: e.student_id, subject_id: e.subject_id, term_id: e.term_id, ca: null, exam: null };
		scores.push(row);
		scoreIndex.set(k, row);
	}
	if (e.ca !== undefined) row.ca = e.ca;
	if (e.exam !== undefined) row.exam = e.exam;
}

const isScoreOrNull = (v: unknown): v is number | null => v === null || (typeof v === 'number' && Number.isFinite(v));

function sanitizeEdit(x: any): ScoreEdit | null {
	if (!x || typeof x.student_id !== 'string' || typeof x.subject_id !== 'string' || typeof x.term_id !== 'string') return null;
	const out: ScoreEdit = { student_id: x.student_id, subject_id: x.subject_id, term_id: x.term_id };
	if ('ca' in x && isScoreOrNull(x.ca)) {
		out.ca = x.ca;
		out.ca_at = typeof x.ca_at === 'string' ? x.ca_at : '';
	}
	if ('exam' in x && isScoreOrNull(x.exam)) {
		out.exam = x.exam;
		out.exam_at = typeof x.exam_at === 'string' ? x.exam_at : '';
	}
	return out.ca === undefined && out.exam === undefined ? null : out;
}

function persistEdits(): SaveStatus {
	if (!hasStorage()) {
		const error = 'This browser is not allowing the app to save on the device';
		patchStatus({ ok: false, error });
		return currentStatus();
	}
	try {
		writeRecord(EDITS, { v: 1, edits: [...edits.values()] });
		patchStatus({ ok: true, error: null, lastSavedAt: new Date().toISOString(), scoreCells: edits.size });
	} catch (e) {
		patchStatus({ ok: false, error: describeError(e), scoreCells: edits.size });
	}
	return currentStatus();
}

function currentStatus(): SaveStatus {
	let s!: SaveStatus;
	saveStatus.subscribe((v) => (s = v))();
	return s;
}

function describeError(e: unknown): string {
	const name = (e as any)?.name;
	if (name === 'QuotaExceededError' || name === 'NS_ERROR_DOM_QUOTA_REACHED') {
		return 'This device is out of storage space for the app';
	}
	return e instanceof Error && e.message ? e.message : 'Saving on this device failed';
}

export interface ScoreChange {
	student_id: string;
	subject_id: string;
	term_id: string;
	field: 'ca' | 'exam';
	/** null clears the cell. */
	value: number | null;
}

/**
 * Records one or many typed scores with a single save to the device. The
 * in-memory data is updated first, so the app is correct even if the save
 * fails; the returned status says whether the device actually kept it.
 */
export function recordScoreChanges(changes: ScoreChange[], at: string = new Date().toISOString()): SaveStatus {
	for (const c of changes) {
		const k = editKey(c.student_id, c.subject_id, c.term_id);
		const e: ScoreEdit = edits.get(k) ?? { student_id: c.student_id, subject_id: c.subject_id, term_id: c.term_id };
		if (c.field === 'ca') {
			e.ca = c.value;
			e.ca_at = at;
		} else {
			e.exam = c.value;
			e.exam_at = at;
		}
		edits.set(k, e);
		applyEditToScores(e);
	}
	return persistEdits();
}

export function getScoreEdits(): ScoreEdit[] {
	return [...edits.values()].map((e) => ({ ...e }));
}

/** A student erased for good takes their typed scores with them. */
export function forgetScoreEditsFor(studentId: string): void {
	let changed = false;
	for (const [k, e] of edits) {
		if (e.student_id === studentId) {
			edits.delete(k);
			changed = true;
		}
	}
	if (changed) persistEdits();
}

export interface MergeResult {
	/** Fields taken from the incoming list (newer, or nothing there before). */
	applied: number;
	/** Fields skipped because this device already holds a newer typed value. */
	keptNewer: number;
	/** Entries that were not valid score edits at all. */
	invalid: number;
	status: SaveStatus;
}

/**
 * Folds another list of edits (a restored backup, or a colleague's copy) into
 * this device, field by field: the most recently typed value wins. Never
 * removes anything, so restoring an old backup cannot undo newer typing.
 */
export function mergeScoreEdits(incoming: unknown[]): MergeResult {
	let applied = 0;
	let keptNewer = 0;
	let invalid = 0;
	for (const raw of incoming) {
		const inc = sanitizeEdit(raw);
		if (!inc) {
			invalid++;
			continue;
		}
		const k = editKey(inc.student_id, inc.subject_id, inc.term_id);
		const cur: ScoreEdit = edits.get(k) ?? { student_id: inc.student_id, subject_id: inc.subject_id, term_id: inc.term_id };
		let touched = false;
		for (const f of ['ca', 'exam'] as const) {
			if (inc[f] === undefined) continue;
			const incAt = (f === 'ca' ? inc.ca_at : inc.exam_at) ?? '';
			const curAt = (f === 'ca' ? cur.ca_at : cur.exam_at);
			if (cur[f] !== undefined && curAt !== undefined && curAt >= incAt) {
				keptNewer++;
				continue;
			}
			cur[f] = inc[f];
			if (f === 'ca') cur.ca_at = incAt;
			else cur.exam_at = incAt;
			applied++;
			touched = true;
		}
		if (touched) {
			edits.set(k, cur);
			applyEditToScores(cur);
		}
	}
	const status = applied > 0 ? persistEdits() : currentStatus();
	return { applied, keptNewer, invalid, status };
}

// ---------------------------------------------------------------------------
// Roster / class / remark changes (unchanged behaviour, safer writes)
// ---------------------------------------------------------------------------

/** Save the roster, class and remark changes. Call after every such change. */
export function persist(): void {
	if (!hasStorage()) return;
	try {
		writeRecord(KEY, { version: DATA_VERSION, students, classes, classSubjects, remarks });
		patchStatus({ ok: true, error: null, lastSavedAt: new Date().toISOString() });
	} catch (e) {
		patchStatus({ ok: false, error: describeError(e) });
	}
}

/**
 * Throw away this device's roster/class changes and go back to the shipped
 * data. Typed scores are kept unless explicitly asked to go too.
 */
export function resetToBaseline(opts: { includeScores?: boolean } = {}): void {
	if (hasStorage()) {
		for (const k of [KEY, `${KEY}_bak`]) localStorage.removeItem(k);
		if (opts.includeScores) for (const k of [EDITS, `${EDITS}_bak`]) localStorage.removeItem(k);
	}
	if (typeof location !== 'undefined') location.reload();
}

// ---------------------------------------------------------------------------
// Asking the browser to keep this storage
// ---------------------------------------------------------------------------

/** Best effort; safe to call repeatedly. Resolves to the browser's answer or null if unsupported. */
export async function requestPersistentStorage(): Promise<boolean | null> {
	try {
		const s = typeof navigator !== 'undefined' ? navigator.storage : undefined;
		if (!s?.persist) return null;
		const already = s.persisted ? await s.persisted() : false;
		const granted = already || (await s.persist());
		patchStatus({ persistent: granted });
		return granted;
	} catch {
		return null;
	}
}

// ---------------------------------------------------------------------------
// Load (runs once, when the app first opens)
// ---------------------------------------------------------------------------

function load(): void {
	if (!hasStorage()) return;

	const baselineScores = new Map(scores.map((r) => [editKey(r.student_id, r.subject_id, r.term_id), { ca: r.ca, exam: r.exam }]));

	// 1. roster/class/remark changes
	let legacyScores: ScoreRecord[] | null = null;
	const saved = readRecord(KEY);
	if (saved) {
		if (Array.isArray(saved.remarks)) replaceContents(remarks, saved.remarks);
		// Older builds kept the entire score table in this record.
		if (Array.isArray(saved.scores)) legacyScores = saved.scores;
		if (saved.version === DATA_VERSION) {
			if (Array.isArray(saved.students)) replaceContents(students, saved.students);
			if (Array.isArray(saved.classes)) replaceContents(classes, saved.classes);
			if (Array.isArray(saved.classSubjects)) replaceContents(classSubjects, saved.classSubjects);
		}
	}

	// 2. score edits
	reindexScores();
	const savedEdits = readRecord(EDITS);
	if (savedEdits && Array.isArray(savedEdits.edits)) {
		for (const raw of savedEdits.edits) {
			const e = sanitizeEdit(raw);
			if (!e) continue;
			edits.set(editKey(e.student_id, e.subject_id, e.term_id), e);
			applyEditToScores(e);
		}
	}

	// 3. one-time upgrade from the old whole-table format: anything that
	// differs from the shipped baseline was typed here, so it becomes an edit
	// (time unknown -> oldest possible, so any dated copy outranks it).
	if (legacyScores && !savedEdits) {
		const unknownTime = '2000-01-01T00:00:00.000Z';
		for (const r of legacyScores) {
			const k = editKey(r.student_id, r.subject_id, r.term_id);
			const base = baselineScores.get(k);
			const e: ScoreEdit = { student_id: r.student_id, subject_id: r.subject_id, term_id: r.term_id };
			if (r.ca !== (base?.ca ?? null)) {
				e.ca = r.ca;
				e.ca_at = unknownTime;
			}
			if (r.exam !== (base?.exam ?? null)) {
				e.exam = r.exam;
				e.exam_at = unknownTime;
			}
			const clean = sanitizeEdit(e);
			if (!clean) continue;
			edits.set(k, clean);
			applyEditToScores(clean);
		}
		persistEdits();
		persist(); // rewrite the roster record without the old score table
	}

	patchStatus({ scoreCells: edits.size });
}

load();

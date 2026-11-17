// ============================================================================
// Getting scores OFF the device, and back on, with no network and no server.
//
// A "scores file" is a small JSON file holding every score this device has
// typed (not the whole school's data) plus who typed it and when. A teacher
// sends it through whatever they already use -- WhatsApp, email, Bluetooth, a
// USB stick -- and the tech team merges every teacher's file into the school
// record with scripts/scores/ingest.py (same hardcode-it-in-the-repo route as
// roster changes). The same file restores a phone that was wiped or replaced.
//
// The file carries a checksum so a file damaged or cut short in transit is
// refused instead of half-applied, and each score carries the student's name
// and the subject name next to the ids so a human (and the ingest script) can
// spot an id that has drifted from the person it should mean.
// ============================================================================

import { students, subjects, currentTerm, DATA_VERSION } from './teacherData';
import { getScoreEdits, mergeScoreEdits, type MergeResult, type ScoreEdit } from './localState';
import { getProfile } from './teacherIdentity';

export const FORMAT = 'tendercare-scores';
const FORMAT_VERSION = 1;

const DEVICE_KEY = 'tc_device_id';
const BACKUP_KEY = 'tc_last_backup';

export interface HandInEdit extends ScoreEdit {
	student_name?: string;
	class_id?: string;
	subject_name?: string;
}

export interface HandIn {
	format: typeof FORMAT;
	version: number;
	exportedAt: string;
	dataVersion: string;
	termId: string;
	device: string;
	teacher: { name: string; subjectIds: string[]; classIds: string[] };
	edits: HandInEdit[];
	/** SHA-256 (hex) of the edits list exactly as written. */
	checksum: string;
}

function deviceId(): string {
	try {
		let id = localStorage.getItem(DEVICE_KEY);
		if (!id) {
			id = (crypto.randomUUID?.() ?? Math.random().toString(36).slice(2)) as string;
			localStorage.setItem(DEVICE_KEY, id);
		}
		return id;
	} catch {
		return 'unknown-device';
	}
}

async function sha256Hex(text: string): Promise<string> {
	const bytes = new TextEncoder().encode(text);
	const digest = await crypto.subtle.digest('SHA-256', bytes);
	return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function buildHandIn(now: Date = new Date()): Promise<HandIn> {
	const byId = new Map(students.map((s) => [s.id, s]));
	const subjectName = new Map(subjects.map((s) => [s.id, s.name]));
	const edits: HandInEdit[] = getScoreEdits()
		.filter((e) => byId.has(e.student_id)) // scores of an erased student are not handed in
		.sort((a, b) => (a.subject_id + a.student_id).localeCompare(b.subject_id + b.student_id))
		.map((e) => ({
			...e,
			student_name: byId.get(e.student_id)!.full_name,
			class_id: byId.get(e.student_id)!.class_id,
			subject_name: subjectName.get(e.subject_id)
		}));
	const profile = getProfile();
	return {
		format: FORMAT,
		version: FORMAT_VERSION,
		exportedAt: now.toISOString(),
		dataVersion: DATA_VERSION,
		termId: currentTerm.id,
		device: deviceId(),
		teacher: { name: profile?.name ?? '', subjectIds: profile?.subjectIds ?? [], classIds: profile?.classIds ?? [] },
		edits,
		checksum: await sha256Hex(JSON.stringify(edits))
	};
}

export function handInFileName(h: HandIn): string {
	const who = (h.teacher.name || 'teacher').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'teacher';
	const d = new Date(h.exportedAt);
	const p = (n: number) => String(n).padStart(2, '0');
	return `tendercare-scores-${who}-${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}.json`;
}

// ---------------------------------------------------------------------------
// Backup bookkeeping (so the app can say how much is not yet handed in)
// ---------------------------------------------------------------------------

export function lastBackupAt(): string | null {
	try {
		return localStorage.getItem(BACKUP_KEY);
	} catch {
		return null;
	}
}

function markBackedUp(at: string): void {
	try {
		localStorage.setItem(BACKUP_KEY, at);
	} catch {
		/* bookkeeping only */
	}
}

/** Number of typed score fields newer than the last file handed in (all of them if none yet). */
export function changesSinceBackup(): number {
	const since = lastBackupAt() ?? '';
	let n = 0;
	for (const e of getScoreEdits()) {
		if (e.ca !== undefined && (e.ca_at ?? '') > since) n++;
		if (e.exam !== undefined && (e.exam_at ?? '') > since) n++;
	}
	return n;
}

// ---------------------------------------------------------------------------
// Sending: share sheet where the phone has one (WhatsApp, email, Bluetooth...),
// otherwise a plain download.
// ---------------------------------------------------------------------------

export type SendOutcome = 'shared' | 'downloaded' | 'cancelled';

function download(file: File): void {
	const url = URL.createObjectURL(file);
	const a = document.createElement('a');
	a.href = url;
	a.download = file.name;
	document.body.appendChild(a);
	a.click();
	a.remove();
	setTimeout(() => URL.revokeObjectURL(url), 10_000);
}

async function toFile(): Promise<{ file: File; hand: HandIn }> {
	const hand = await buildHandIn();
	const file = new File([JSON.stringify(hand, null, 1)], handInFileName(hand), { type: 'application/json' });
	return { file, hand };
}

/** Opens the phone's share sheet with the scores file; falls back to downloading it. */
export async function sendScoresFile(): Promise<SendOutcome> {
	const { file, hand } = await toFile();
	const nav = navigator as Navigator & { canShare?: (d: ShareData) => boolean };
	if (nav.share && nav.canShare?.({ files: [file] })) {
		try {
			await nav.share({
				files: [file],
				title: 'Tendercare scores',
				text: `Scores from ${hand.teacher.name || 'a teacher'} (${hand.edits.length} entries)`
			});
			markBackedUp(hand.exportedAt);
			return 'shared';
		} catch (e) {
			if ((e as Error)?.name === 'AbortError') return 'cancelled';
			// Any other share failure: fall through to a plain download.
		}
	}
	download(file);
	markBackedUp(hand.exportedAt);
	return 'downloaded';
}

// ---------------------------------------------------------------------------
// Roster file: this phone's own roster, classes and departments, exactly as
// saved here -- including a copy saved under an OLDER build, which the app no
// longer shows once a new roster ships but leaves untouched in storage until
// the next roster change on this phone. The tech team applies it centrally
// (scripts/roster/apply_changes.py); nothing on the phone changes by sending it.
// ---------------------------------------------------------------------------

export const ROSTER_FORMAT = 'tendercare-roster';
const ROSTER_KEYS = ['tc_local_state', 'tc_local_state_bak'] as const;

function rawRecord(key: string): unknown {
	try {
		const text = localStorage.getItem(key);
		return text ? JSON.parse(text) : null;
	} catch {
		return null;
	}
}

/** True if this phone holds any saved roster changes (current or from an older build). */
export function hasRosterOnPhone(): boolean {
	return ROSTER_KEYS.some((k) => {
		const r = rawRecord(k) as { students?: unknown } | null;
		return !!r && Array.isArray(r.students);
	});
}

export async function sendRosterFile(now: Date = new Date()): Promise<SendOutcome> {
	const profile = getProfile();
	const records = Object.fromEntries(ROSTER_KEYS.map((k) => [k, rawRecord(k)]));
	const body = {
		format: ROSTER_FORMAT,
		version: 1,
		exportedAt: now.toISOString(),
		appDataVersion: DATA_VERSION,
		device: deviceId(),
		teacher: { name: profile?.name ?? '' },
		records,
		checksum: await sha256Hex(JSON.stringify(records))
	};
	const who = (profile?.name || 'teacher').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'teacher';
	const p = (n: number) => String(n).padStart(2, '0');
	const name = `tendercare-roster-${who}-${now.getFullYear()}${p(now.getMonth() + 1)}${p(now.getDate())}-${p(now.getHours())}${p(now.getMinutes())}.json`;
	const file = new File([JSON.stringify(body)], name, { type: 'application/json' });
	const nav = navigator as Navigator & { canShare?: (d: ShareData) => boolean };
	if (nav.share && nav.canShare?.({ files: [file] })) {
		try {
			await nav.share({ files: [file], title: 'Tendercare roster', text: `Roster from ${profile?.name || 'a teacher'}` });
			return 'shared';
		} catch (e) {
			if ((e as Error)?.name === 'AbortError') return 'cancelled';
		}
	}
	download(file);
	return 'downloaded';
}

/** Saves the scores file to the phone without the share sheet. */
export async function saveScoresFile(): Promise<void> {
	const { file, hand } = await toFile();
	download(file);
	markBackedUp(hand.exportedAt);
}

// ---------------------------------------------------------------------------
// Receiving: validate completely before touching anything.
// ---------------------------------------------------------------------------

export interface ReadResult {
	ok: boolean;
	problem?: string;
	hand?: HandIn;
}

export async function readScoresFile(text: string): Promise<ReadResult> {
	let h: any;
	try {
		h = JSON.parse(text);
	} catch {
		return { ok: false, problem: 'This is not a scores file (it could not be read).' };
	}
	if (!h || h.format !== FORMAT) return { ok: false, problem: 'This is not a Tendercare scores file.' };
	if (h.version !== FORMAT_VERSION) return { ok: false, problem: 'This scores file is from a different version of the app.' };
	if (!Array.isArray(h.edits)) return { ok: false, problem: 'The scores file is damaged (no scores inside).' };
	if ((await sha256Hex(JSON.stringify(h.edits))) !== h.checksum) {
		return { ok: false, problem: 'The scores file is damaged or incomplete (it changed after it was made). Ask for it to be sent again.' };
	}
	return { ok: true, hand: h as HandIn };
}

export interface RestoreOutcome extends Partial<MergeResult> {
	ok: boolean;
	problem?: string;
}

/** Merges a scores file into this device. Newest-typed value wins per field; nothing is deleted. */
export async function restoreScoresFile(file: File): Promise<RestoreOutcome> {
	const r = await readScoresFile(await file.text());
	if (!r.ok || !r.hand) return { ok: false, problem: r.problem };
	const m = mergeScoreEdits(r.hand.edits);
	return { ok: m.status.ok, problem: m.status.ok ? undefined : (m.status.error ?? undefined), ...m };
}

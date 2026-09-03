import { supabase } from '$lib/supabase';
import { readThroughCache, enqueueWrite, isOnline, cacheRead, cacheWrite } from '$lib/offline';
import { get } from 'svelte/store';

export interface Subject {
	id: string;
	name: string;
}

export interface ClassRow {
	id: string;
	label: string;
}

export interface ScoreEntry {
	student_id: string;
	ca: number | null;
	exam: number | null;
}

/**
 * Every subject in the school. No per-teacher filtering here — auth is
 * still the two shared staff/admin accounts (see login/+page.svelte's
 * comment), so there's no `staff_subjects` mapping to filter against yet.
 * Any signed-in staff account can enter scores for any subject/class.
 */
export async function listSubjects(): Promise<Subject[]> {
	const result = await readThroughCache('subjects:all', async () => {
		const { data, error } = await supabase.from('subjects').select('id, name').order('name');
		if (error) throw error;
		return data as Subject[];
	});
	return result.data;
}

/** Classes that actually study a given subject, via class_subjects. */
export async function listClassesForSubject(subjectId: string): Promise<ClassRow[]> {
	const result = await readThroughCache(`classesForSubject:${subjectId}`, async () => {
		const { data, error } = await supabase
			.from('class_subjects')
			.select('classes(id, label)')
			.eq('subject_id', subjectId)
			.order('class_id');
		if (error) throw error;
		return (data ?? []).map((r: any) => r.classes).filter(Boolean) as ClassRow[];
	});
	return result.data;
}

/**
 * Existing CA/Exam rows for a class's active roster, for one subject and
 * term. Students with no row yet simply haven't been scored — the sheet
 * fills those in as 0/blank rather than treating it as an error.
 */
/**
 * Existing CA/Exam rows for a class's active roster, for one subject and
 * term. Students with no row yet simply haven't been scored — the sheet
 * fills those in as 0/blank rather than treating it as an error.
 *
 * Cached per-student (not as one batch blob), so a single offline
 * saveScore() can patch exactly the one entry it affects (see below)
 * without invalidating every other student's cached score in the same
 * class.
 */
export async function listScores(
	studentIds: string[],
	subjectId: string,
	termId: string
): Promise<Map<string, ScoreEntry>> {
	if (studentIds.length === 0) return new Map();

	const cacheKey = (id: string) => `score:${subjectId}:${termId}:${id}`;
	let rows: ScoreEntry[] | null = null;

	try {
		const { data, error } = await Promise.race([
			supabase
				.from('scores')
				.select('student_id, ca, exam')
				.eq('subject_id', subjectId)
				.eq('term_id', termId)
				.in('student_id', studentIds),
			new Promise<never>((_, reject) =>
				setTimeout(() => reject(new Error('offline-timeout')), 6000)
			)
		]);
		if (error) throw error;
		rows = (data ?? []) as ScoreEntry[];

		const byId = new Map(rows.map((r) => [r.student_id, r]));
		for (const id of studentIds) {
			// Cache an explicit null for "confirmed no score yet", distinct
			// from "never fetched", so a later offline read doesn't show a
			// stale value from some earlier, now-superseded cache entry.
			await cacheWrite(cacheKey(id), byId.get(id) ?? null);
		}
	} catch {
		rows = [];
		for (const id of studentIds) {
			const cached = await cacheRead<ScoreEntry | null>(cacheKey(id));
			if (cached && cached.data) rows.push(cached.data);
		}
	}

	const map = new Map<string, ScoreEntry>();
	for (const row of rows) map.set(row.student_id, row);
	return map;
}

/**
 * Write one student's CA and/or Exam for a subject/term. Upsert on the
 * table's (student_id, subject_id, term_id) unique constraint — the same
 * shape as every other write in this app (see roster.ts), one round trip
 * per save rather than a delete-then-insert. This shape is exactly why
 * it's safe to queue offline: replaying the same upsert twice (e.g. if a
 * sync gets interrupted partway) lands on the same final value, never a
 * duplicate row.
 *
 * If the live write fails (offline, or the connection drops mid-request),
 * this queues it instead of throwing, and optimistically patches the
 * local per-student cache so the sheet reflects the change immediately —
 * the same student re-opened offline shows what was just typed, not the
 * old synced value. get(isOnline) is checked first purely to skip the
 * live attempt entirely when we already know we're offline, rather than
 * waiting out the timeout every time.
 */
export async function saveScore(
	studentId: string,
	subjectId: string,
	termId: string,
	field: 'ca' | 'exam',
	value: number
): Promise<void> {
	const payload = { studentId, subjectId, termId, field, value };

	if (get(isOnline)) {
		try {
			await writeScoreLive(payload);
			return;
		} catch {
			// fall through to queue
		}
	}

	await enqueueWrite('saveScore', payload);
	const cacheKey = `score:${subjectId}:${termId}:${studentId}`;
	const existing = await cacheRead<ScoreEntry | null>(cacheKey);
	const merged: ScoreEntry = {
		student_id: studentId,
		ca: existing?.data?.ca ?? null,
		exam: existing?.data?.exam ?? null,
		[field]: value
	} as ScoreEntry;
	await cacheWrite(cacheKey, merged);
}

interface SaveScorePayload {
	studentId: string;
	subjectId: string;
	termId: string;
	field: 'ca' | 'exam';
	value: number;
}

async function writeScoreLive(payload: SaveScorePayload): Promise<void> {
	const {
		data: { user }
	} = await supabase.auth.getUser();
	const { error } = await supabase
		.from('scores')
		.upsert(
			{
				student_id: payload.studentId,
				subject_id: payload.subjectId,
				term_id: payload.termId,
				[payload.field]: payload.value,
				entered_by: user?.id ?? null,
				updated_at: new Date().toISOString()
			},
			{ onConflict: 'student_id,subject_id,term_id' }
		);
	if (error) throw error;
}

/** Registered for offline.ts's flushOutbox() to replay queued score saves. */
export const scoreOutboxHandlers = {
	saveScore: (payload: SaveScorePayload) => writeScoreLive(payload)
};

/**
 * Nigerian A1–F9 grading band, same boundaries used by the report-pipeline
 * generator (report-pipeline/generate.py's remark_for()) so a score's
 * grade never disagrees between this sheet and the printed transcript.
 */
export function nigerianGrade(total: number, maxCA: number, maxExam: number): string {
	const maxTotal = maxCA + maxExam;
	const pct = maxTotal > 0 ? (total / maxTotal) * 100 : 0;
	if (pct >= 75) return 'A1';
	if (pct >= 70) return 'B2';
	if (pct >= 65) return 'B3';
	if (pct >= 60) return 'C4';
	if (pct >= 55) return 'C5';
	if (pct >= 50) return 'C6';
	if (pct >= 45) return 'D7';
	if (pct >= 40) return 'E8';
	return 'F9';
}

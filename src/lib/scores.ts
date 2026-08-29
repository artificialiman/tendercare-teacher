import { supabase } from '$lib/supabase';

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
	const { data, error } = await supabase.from('subjects').select('id, name').order('name');
	if (error) throw error;
	return data as Subject[];
}

/** Classes that actually study a given subject, via class_subjects. */
export async function listClassesForSubject(subjectId: string): Promise<ClassRow[]> {
	const { data, error } = await supabase
		.from('class_subjects')
		.select('classes(id, label)')
		.eq('subject_id', subjectId)
		.order('class_id');
	if (error) throw error;
	return (data ?? []).map((r: any) => r.classes).filter(Boolean) as ClassRow[];
}

/**
 * Existing CA/Exam rows for a class's active roster, for one subject and
 * term. Students with no row yet simply haven't been scored — the sheet
 * fills those in as 0/blank rather than treating it as an error.
 */
export async function listScores(
	studentIds: string[],
	subjectId: string,
	termId: string
): Promise<Map<string, ScoreEntry>> {
	if (studentIds.length === 0) return new Map();
	const { data, error } = await supabase
		.from('scores')
		.select('student_id, ca, exam')
		.eq('subject_id', subjectId)
		.eq('term_id', termId)
		.in('student_id', studentIds);
	if (error) throw error;
	const map = new Map<string, ScoreEntry>();
	for (const row of (data ?? []) as ScoreEntry[]) map.set(row.student_id, row);
	return map;
}

/**
 * Write one student's CA and/or Exam for a subject/term. Upsert on the
 * table's (student_id, subject_id, term_id) unique constraint — the same
 * shape as every other write in this app (see roster.ts), one round trip
 * per save rather than a delete-then-insert.
 */
export async function saveScore(
	studentId: string,
	subjectId: string,
	termId: string,
	field: 'ca' | 'exam',
	value: number
): Promise<void> {
	const {
		data: { user }
	} = await supabase.auth.getUser();
	const { error } = await supabase
		.from('scores')
		.upsert(
			{
				student_id: studentId,
				subject_id: subjectId,
				term_id: termId,
				[field]: value,
				entered_by: user?.id ?? null,
				updated_at: new Date().toISOString()
			},
			{ onConflict: 'student_id,subject_id,term_id' }
		);
	if (error) throw error;
}

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

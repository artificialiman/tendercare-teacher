import { subjects, classes, classSubjects, scores, students, terms, currentTerm } from './teacherData';
import { recordScoreChanges, type SaveStatus, type ScoreChange } from './localState';
import type { Student } from './roster';

// Plain functions over the hardcoded data in teacherData.ts, with changes
// saved on this device by localState.ts. No network, no cache, no outbox: a
// score typed here is in memory and in localStorage before the call returns.

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

/** Default maximums for the sheet and broadsheet; the score sheet lets a teacher change them. */
export const DEFAULT_MAX_CA = 30;
export const DEFAULT_MAX_EXAM = 70;

/** CA/exam scores for a set of students in one subject and term. */
export async function listScores(
	studentIds: string[],
	subjectId: string,
	termId: string
): Promise<Map<string, ScoreEntry>> {
	const wanted = new Set(studentIds);
	const map = new Map<string, ScoreEntry>();
	for (const s of scores) {
		if (s.subject_id === subjectId && s.term_id === termId && wanted.has(s.student_id)) {
			map.set(s.student_id, { student_id: s.student_id, ca: s.ca, exam: s.exam });
		}
	}
	return map;
}

/**
 * Saves one field (CA or exam) for one student. `null` clears the cell. The
 * returned status says whether this device actually kept it -- callers show
 * that rather than assuming.
 */
export async function saveScore(
	studentId: string,
	subjectId: string,
	termId: string,
	field: 'ca' | 'exam',
	value: number | null
): Promise<SaveStatus> {
	return recordScoreChanges([{ student_id: studentId, subject_id: subjectId, term_id: termId, field, value }]);
}

/** Many fields in one save to the device (used by "Clear all"). */
export async function saveScores(changes: ScoreChange[]): Promise<SaveStatus> {
	return recordScoreChanges(changes);
}

/** The term every sheet is being filled for. */
export async function getCurrentTerm(): Promise<{ id: string; academic_year: string; term_number: number } | null> {
	return currentTerm ?? null;
}

export interface SheetProgress {
	filled: number;
	total: number;
	pct: number;
}

/** How much of one subject's sheet for one class is filled in for a term. */
export async function sheetProgress(subjectId: string, classId: string, termId: string): Promise<SheetProgress> {
	const classStudents = new Set(students.filter((s) => s.class_id === classId && s.active).map((s) => s.id));
	let filled = 0;
	for (const r of scores) {
		if (r.subject_id !== subjectId || r.term_id !== termId || !classStudents.has(r.student_id)) continue;
		if (r.ca !== null || r.exam !== null) filled++;
	}
	const total = classStudents.size;
	return { filled, total, pct: total > 0 ? Math.round((filled / total) * 100) : 0 };
}

// ---------------------------------------------------------------------------
// Broadsheet (read-only)
// ---------------------------------------------------------------------------

export interface BroadsheetCell {
	ca: number | null;
	exam: number | null;
	total: number | null;
}

export interface BroadsheetRow {
	student: Student;
	cells: Record<string, BroadsheetCell>; // by subject id
	grandTotal: number;
	scoredSubjects: number;
}

export interface Broadsheet {
	classId: string;
	subjects: Subject[];
	rows: BroadsheetRow[];
}

/**
 * Every active student in a class against the given subjects, for one term.
 * Only subjects the class actually studies are included. Never writes.
 */
export function buildBroadsheet(classId: string, subjectIds: string[], termId: string): Broadsheet {
	const studied = new Set(classSubjects.filter((cs) => cs.class_id === classId).map((cs) => cs.subject_id));
	const cols = subjects.filter((s) => subjectIds.includes(s.id) && studied.has(s.id)).sort((a, b) => a.name.localeCompare(b.name));

	const byKey = new Map<string, { ca: number | null; exam: number | null }>();
	for (const r of scores) if (r.term_id === termId) byKey.set(`${r.student_id}:${r.subject_id}`, r);

	const rows = students
		.filter((s) => s.class_id === classId && s.active)
		.sort((a, b) => a.full_name.localeCompare(b.full_name))
		.map((student) => {
			const cells: Record<string, BroadsheetCell> = {};
			let grandTotal = 0;
			let scoredSubjects = 0;
			for (const sub of cols) {
				const r = byKey.get(`${student.id}:${sub.id}`);
				const ca = r?.ca ?? null;
				const exam = r?.exam ?? null;
				const total = ca === null && exam === null ? null : (ca ?? 0) + (exam ?? 0);
				cells[sub.id] = { ca, exam, total };
				if (total !== null) {
					grandTotal += total;
					scoredSubjects++;
				}
			}
			return { student, cells, grandTotal, scoredSubjects };
		});

	return { classId, subjects: cols, rows };
}

/** All terms, newest first, for the broadsheet's term picker. */
export function listTerms() {
	return [...terms].sort((a, b) => b.id.localeCompare(a.id));
}

/**
 * Nigerian A1-F9 grading band, same boundaries used by the report-pipeline
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

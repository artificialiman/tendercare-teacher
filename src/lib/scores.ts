import { subjects, classes, classSubjects, scores } from './teacherData';

// Plain operations on the hardcoded arrays in teacherData.ts. Same exported
// names/signatures as before, so the score pages only needed their auth
// blocks dropped. No database, no cache, no outbox: a write lands in the
// array immediately and a reload resets it.

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

/** Every subject in the school, by name. */
export async function listSubjects(): Promise<Subject[]> {
	return [...subjects].sort((a, b) => a.name.localeCompare(b.name));
}

/** Every class that studies a given subject, in class order. */
export async function listClassesForSubject(subjectId: string): Promise<ClassRow[]> {
	const ids = new Set(classSubjects.filter((cs) => cs.subject_id === subjectId).map((cs) => cs.class_id));
	return classes
		.filter((c) => ids.has(c.id))
		.sort((a, b) => a.sort_order - b.sort_order)
		.map((c) => ({ id: c.id, label: c.label }));
}

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

/** Saves one field (CA or exam) for one student, creating the row if needed. */
export async function saveScore(
	studentId: string,
	subjectId: string,
	termId: string,
	field: 'ca' | 'exam',
	value: number
): Promise<void> {
	const existing = scores.find(
		(s) => s.student_id === studentId && s.subject_id === subjectId && s.term_id === termId
	);
	if (existing) {
		existing[field] = value;
	} else {
		scores.push({ student_id: studentId, subject_id: subjectId, term_id: termId, ca: null, exam: null, [field]: value });
	}
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

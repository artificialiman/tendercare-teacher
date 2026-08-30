import { supabase } from '$lib/supabase';
import { listClasses, type ClassInfo } from '$lib/roster';

/**
 * Same 40% class-completeness gate report-pipeline/generate.py uses
 * (CLASS_PUBLISH_THRESHOLD) -- a class/subject only counts as "real" for
 * an average once at least this fraction of its active students have a
 * total for it this term. Keeps this dashboard from showing a
 * barely-started term's average as if it meant something.
 */
const COMPLETENESS_THRESHOLD = 0.4;

interface ScoreRow {
	student_id: string;
	subject_id: string;
	ca: number | null;
	exam: number | null;
	students: { class_id: string; active: boolean } | null;
}

async function loadTermScores(termId: string): Promise<ScoreRow[]> {
	const { data, error } = await supabase
		.from('scores')
		.select('student_id, subject_id, ca, exam, students!inner(class_id, active)')
		.eq('term_id', termId);
	if (error) throw error;
	return (data ?? []) as unknown as ScoreRow[];
}

async function activeCountByClass(): Promise<Map<string, number>> {
	const { data, error } = await supabase.from('students').select('class_id').eq('active', true);
	if (error) throw error;
	const map = new Map<string, number>();
	for (const row of data ?? []) map.set(row.class_id, (map.get(row.class_id) ?? 0) + 1);
	return map;
}

export interface SubjectAverage {
	subjectId: string;
	subjectName: string;
	average: number;
	classesCounted: number;
}

/**
 * Average total (CA+Exam) per subject, current term, school-wide --
 * subject performance, not enrollment. Only counts a class/subject
 * combination once it clears the 40% gate, so a subject taught in 8
 * classes but only fully entered in 3 shows an honest 3-class average,
 * not a diluted one padded by empty cells.
 */
export async function listSubjectAverages(termId: string): Promise<SubjectAverage[]> {
	const [{ data: subjects, error: subErr }, scores, activeByClass] = await Promise.all([
		supabase.from('subjects').select('id, name'),
		loadTermScores(termId),
		activeCountByClass()
	]);
	if (subErr) throw subErr;

	// group scores by subject -> class -> [totals]
	const bySubjectClass = new Map<string, Map<string, number[]>>();
	for (const row of scores) {
		if (!row.students?.active || row.ca == null || row.exam == null) continue;
		const cls = row.students.class_id;
		let byClass = bySubjectClass.get(row.subject_id);
		if (!byClass) {
			byClass = new Map();
			bySubjectClass.set(row.subject_id, byClass);
		}
		const arr = byClass.get(cls) ?? [];
		arr.push(Number(row.ca) + Number(row.exam));
		byClass.set(cls, arr);
	}

	const results: SubjectAverage[] = [];
	for (const subj of subjects ?? []) {
		const byClass = bySubjectClass.get(subj.id);
		if (!byClass) continue;
		let sum = 0;
		let count = 0;
		let classesCounted = 0;
		for (const [classId, totals] of byClass) {
			const activeInClass = activeByClass.get(classId) ?? 0;
			if (activeInClass === 0 || totals.length / activeInClass < COMPLETENESS_THRESHOLD) continue;
			sum += totals.reduce((a, b) => a + b, 0);
			count += totals.length;
			classesCounted++;
		}
		if (count === 0) continue;
		results.push({
			subjectId: subj.id,
			subjectName: subj.name,
			average: Math.round((sum / count) * 10) / 10,
			classesCounted
		});
	}
	return results.sort((a, b) => b.average - a.average);
}

export interface ClassAverage {
	classId: string;
	classLabel: string;
	stage: 'JSS' | 'SS';
	level: 1 | 2 | 3;
	graduatingYear: number; // computed "set" -- see gradYearFor()
	average: number | null; // null = below the 40% gate
	studentCount: number;
}

/**
 * A class's expected graduation calendar year, computed from stage/level
 * against the term's own academic year -- not a stored field. JSS1 has
 * 5 years left (2 more JSS + 3 SS), SS3 has 0. This is Claude's own
 * labeling convention for "set", not something stated -- easy to adjust
 * if the school's actual "Set of <year>" convention differs.
 */
function gradYearFor(stage: 'JSS' | 'SS', level: number, academicYearEndLabel: number): number {
	const yearsLeft = stage === 'JSS' ? 3 - level + 3 : 3 - level;
	return academicYearEndLabel + yearsLeft;
}

function academicYearEnd(academicYear: string): number {
	// "2024/2025" -> 2025
	const parts = academicYear.split('/');
	return Number(parts[1] ?? parts[0]);
}

/**
 * Per-class average for a given term, gated the same way as subject
 * averages. Carries stage/level/graduatingYear so the page can regroup
 * by stage or by "set" without a second query.
 */
export async function listClassAverages(termId: string, academicYear: string): Promise<ClassAverage[]> {
	const [classes, scores, activeByClass] = await Promise.all([
		listClasses(),
		loadTermScores(termId),
		activeCountByClass()
	]);

	const byClass = new Map<string, number[]>();
	for (const row of scores) {
		if (!row.students?.active || row.ca == null || row.exam == null) continue;
		const arr = byClass.get(row.students.class_id) ?? [];
		arr.push(Number(row.ca) + Number(row.exam));
		byClass.set(row.students.class_id, arr);
	}

	const endYear = academicYearEnd(academicYear);
	return classes.map((c) => {
		const totals = byClass.get(c.id) ?? [];
		const activeInClass = activeByClass.get(c.id) ?? 0;
		const clears = activeInClass > 0 && totals.length / activeInClass >= COMPLETENESS_THRESHOLD;
		return {
			classId: c.id,
			classLabel: c.label,
			stage: c.stage,
			level: c.level,
			graduatingYear: gradYearFor(c.stage, c.level, endYear),
			average: clears ? Math.round((totals.reduce((a, b) => a + b, 0) / totals.length) * 10) / 10 : null,
			studentCount: activeInClass
		};
	});
}

export interface ClassEntryCompletion {
	classId: string;
	classLabel: string;
	filledCells: number;
	expectedCells: number;
	percent: number;
}

/**
 * Score-entry / broadsheet completion per class: how many (student x
 * subject) cells are filled versus how many the class actually needs,
 * from class_subjects -- not every class studies every subject.
 * Doubles as the honest proxy for "result/transcript upload
 * completeness": a class only produces a real (non-placeholder)
 * transcript once generate.py's own 40% gate clears, and that gate is
 * exactly this same fill percentage. There's no live signal from the
 * actual generated-file count here -- that lives in a separate repo
 * (tendercare-portal/static/reports) this app has no read access to
 * without a synced manifest, which doesn't exist yet.
 */
export async function listScoreEntryCompletion(termId: string): Promise<ClassEntryCompletion[]> {
	const [classes, { data: classSubjects, error: csErr }, scores, activeByClass] = await Promise.all([
		listClasses(),
		supabase.from('class_subjects').select('class_id, subject_id'),
		loadTermScores(termId),
		activeCountByClass()
	]);
	if (csErr) throw csErr;

	const subjectsByClass = new Map<string, number>();
	for (const row of classSubjects ?? []) {
		subjectsByClass.set(row.class_id, (subjectsByClass.get(row.class_id) ?? 0) + 1);
	}

	const filledByClass = new Map<string, Set<string>>(); // class -> set of `${student}:${subject}` with both ca+exam present
	for (const row of scores) {
		if (!row.students?.active || row.ca == null || row.exam == null) continue;
		const cls = row.students.class_id;
		const set = filledByClass.get(cls) ?? new Set();
		set.add(`${row.student_id}:${row.subject_id}`);
		filledByClass.set(cls, set);
	}

	return classes.map((c) => {
		const activeInClass = activeByClass.get(c.id) ?? 0;
		const subjectCount = subjectsByClass.get(c.id) ?? 0;
		const expectedCells = activeInClass * subjectCount;
		const filledCells = filledByClass.get(c.id)?.size ?? 0;
		return {
			classId: c.id,
			classLabel: c.label,
			filledCells,
			expectedCells,
			percent: expectedCells > 0 ? Math.round((filledCells / expectedCells) * 100) : 0
		};
	});
}

export interface NewStudent {
	id: string;
	full_name: string;
	class_id: string;
	created_at: string;
}

/**
 * Most recently created students -- new admissions and transfers-in.
 * `terms` has no start-date column (only academic_year/term_number/
 * is_current), so "since the current term started" genuinely can't be
 * computed from the schema as it stands -- this is a recent-window
 * proxy (default 60 days) instead, newest first. "New classes" can be
 * read off this same list: any class_id appearing here that isn't in
 * `classes` yet (a class add_class() just created) is new by
 * definition, not something this function has to infer separately.
 */
export async function listNewStudents(sinceDays = 60): Promise<NewStudent[]> {
	const since = new Date(Date.now() - sinceDays * 24 * 60 * 60 * 1000).toISOString();
	const { data, error } = await supabase
		.from('students')
		.select('id, full_name, class_id, created_at')
		.gte('created_at', since)
		.order('created_at', { ascending: false });
	if (error) throw error;
	return (data ?? []) as NewStudent[];
}

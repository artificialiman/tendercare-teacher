// ============================================================================
// Hardcoded data for the teacher app. No Supabase, no auth, no fetch, no
// mock client pretending to be one -- plain arrays, mutated directly by
// roster.ts/scores.ts. This is a real, standalone state of the app, not a
// demo toggle: auth and a real backend come back later, as their own
// piece of work, not as something half-wired-up sitting dormant here.
//
// Placeholder names throughout -- there's no real roster to hand this yet.
// Replace these arrays with the real roster/scores when that's ready;
// everything that reads them (roster.ts, scores.ts) doesn't care where
// the data comes from, only that these arrays exist and have this shape.
// ============================================================================

import type { Student } from './roster';

export interface ClassRecord {
	id: string;
	label: string;
	arm: string;
	stage: 'JSS' | 'SS';
	level: 1 | 2 | 3;
	sort_order: number;
}

export interface SubjectRecord {
	id: string;
	name: string;
}

export interface ClassSubjectRecord {
	class_id: string;
	subject_id: string;
}

export interface ScoreRecord {
	student_id: string;
	subject_id: string;
	term_id: string;
	ca: number | null;
	exam: number | null;
}

export interface RemarkRecord {
	student_id: string;
	term_id: string;
	teacher_remark: string | null;
	principal_remark: string | null;
}

export interface TermRecord {
	id: string;
	academic_year: string;
	term_number: number;
	is_current: boolean;
}

export const terms: TermRecord[] = [
	{ id: 'term-2025-3', academic_year: '2025/2026', term_number: 3, is_current: true }
];

export const currentTerm = terms.find((t) => t.is_current)!;

export const classes: ClassRecord[] = [
	{ id: 'JSS1A', label: 'JSS1A', arm: 'A', stage: 'JSS', level: 1, sort_order: 1 },
	{ id: 'JSS1B', label: 'JSS1B', arm: 'B', stage: 'JSS', level: 1, sort_order: 2 },
	{ id: 'JSS2A', label: 'JSS2A', arm: 'A', stage: 'JSS', level: 2, sort_order: 3 },
	{ id: 'JSS2B', label: 'JSS2B', arm: 'B', stage: 'JSS', level: 2, sort_order: 4 },
	{ id: 'JSS3A', label: 'JSS3A', arm: 'A', stage: 'JSS', level: 3, sort_order: 5 },
	{ id: 'JSS3B', label: 'JSS3B', arm: 'B', stage: 'JSS', level: 3, sort_order: 6 },
	{ id: 'SS1 Science', label: 'SS1 Science', arm: 'Science', stage: 'SS', level: 1, sort_order: 7 },
	{ id: 'SS1 Actuarial', label: 'SS1 Actuarial', arm: 'Actuarial', stage: 'SS', level: 1, sort_order: 8 },
	{ id: 'SS2 Science', label: 'SS2 Science', arm: 'Science', stage: 'SS', level: 2, sort_order: 9 },
	{ id: 'SS2 Actuarial', label: 'SS2 Actuarial', arm: 'Actuarial', stage: 'SS', level: 2, sort_order: 10 },
	{ id: 'SS3 Science', label: 'SS3 Science', arm: 'Science', stage: 'SS', level: 3, sort_order: 11 },
	{ id: 'SS3 Actuarial', label: 'SS3 Actuarial', arm: 'Actuarial', stage: 'SS', level: 3, sort_order: 12 }
];

export const subjects: SubjectRecord[] = [
	{ id: 'sub-math', name: 'Mathematics' },
	{ id: 'sub-eng', name: 'English Language' },
	{ id: 'sub-basci', name: 'Basic Science' },
	{ id: 'sub-social', name: 'Social Studies' },
	{ id: 'sub-dt', name: 'Digital Technology' },
	{ id: 'sub-phe', name: 'Physical & Health Education' }
];

// Every class studies every subject -- simplest placeholder shape.
export const classSubjects: ClassSubjectRecord[] = classes.flatMap((c) =>
	subjects.map((s) => ({ class_id: c.id, subject_id: s.id }))
);

const FIRST_NAMES = [
	'Chidinma', 'Oluwaseun', 'Ifeoma', 'Tobiloba', 'Amara', 'Chukwuemeka',
	'Folasade', 'Ikenna', 'Ngozi', 'Babatunde', 'Adaeze', 'Chiamaka',
	'Oluwadamilare', 'Ebuka', 'Temitope', 'Chinwe', 'Olumide', 'Zainab',
	'Kelechi', 'Funmilayo', 'Obinna', 'Aisha', 'Emeka', 'Bisi',
	'Chukwudi', 'Halima', 'Yusuf', 'Nkechi', 'Segun', 'Blessing',
	'Tochukwu', 'Rasheedat', 'Chinedu', 'Omolara', 'Uche', 'Hadiza'
];
const LAST_NAMES = [
	'Okafor', 'Adebayo', 'Eze', 'Balogun', 'Nwosu', 'Olatunji', 'Igwe',
	'Afolabi', 'Chukwu', 'Ogunleye', 'Udo', 'Bello', 'Okonkwo', 'Adeyemi',
	'Nnamdi', 'Ajayi', 'Obi', 'Lawal', 'Chijioke', 'Oyelaran', 'Madu',
	'Fashola', 'Anyanwu', 'Adeleke', 'Nwankwo', 'Okoro', 'Suleiman',
	'Ibeh', 'Osagie', 'Bakare', 'Chidozie', 'Agboola', 'Nnaji', 'Yakubu',
	'Opara', 'Danjuma'
];

function buildPlaceholderStudents(): Student[] {
	const result: Student[] = [];
	let n = 0;
	for (const cls of classes) {
		for (let i = 0; i < 3; i++) {
			const idx = n % FIRST_NAMES.length;
			n++;
			const full_name = `${FIRST_NAMES[idx]} ${LAST_NAMES[(idx + i) % LAST_NAMES.length]}`;
			result.push({
				id: `TCH-TMP-${String(n).padStart(3, '0')}`,
				full_name,
				class_id: cls.id,
				active: true,
				created_at: '2025-09-01T08:00:00.000Z',
				deleted_at: null,
				repeating: false,
				repeat_assigned_at: null,
				repeat_pardoned_at: null,
				portrait_url: null,
				bio: null
			});
		}
	}
	return result;
}

export const students: Student[] = buildPlaceholderStudents();

function seededScore(seed: number, max: number): number {
	const x = Math.sin(seed) * 10000;
	const frac = x - Math.floor(x);
	return Math.round(frac * max);
}

function buildPlaceholderScores(): ScoreRecord[] {
	const result: ScoreRecord[] = [];
	let seed = 1;
	for (const student of students) {
		for (const subject of subjects) {
			seed++;
			if (seed % 5 < 2) continue; // leave some cells unfilled, same as a real in-progress term
			result.push({
				student_id: student.id,
				subject_id: subject.id,
				term_id: currentTerm.id,
				ca: seededScore(seed, 40),
				exam: seededScore(seed * 1.7, 60)
			});
		}
	}
	return result;
}

export const scores: ScoreRecord[] = buildPlaceholderScores();

export const remarks: RemarkRecord[] = [];

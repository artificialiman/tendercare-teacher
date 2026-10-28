// ============================================================================
// On-device persistence for the hardcoded data. Nothing here touches a
// network: teacherData.ts is the baseline that ships with the app, and what a
// teacher changes on top of it (scores typed, students added/removed/moved,
// arms added) is saved in this browser's localStorage so a reload keeps it.
//
// That also means those changes live only on this device. There is no path
// back to the admin database yet -- that arrives together with real auth.
//
// Version rule: if the baseline was regenerated (new DATA_VERSION), saved
// roster/class edits are discarded because they sat on a different baseline,
// but scores are always kept -- they are keyed by student/subject/term, so
// they stay valid.
// ============================================================================

import { DATA_VERSION, students, classes, classSubjects, scores, remarks } from './teacherData';

const KEY = 'tc_local_state';

function replaceContents<T>(target: T[], next: T[]): void {
	target.splice(0, target.length, ...next);
}

function load(): void {
	if (typeof localStorage === 'undefined') return;
	try {
		const raw = localStorage.getItem(KEY);
		if (!raw) return;
		const saved = JSON.parse(raw);
		if (Array.isArray(saved.scores)) replaceContents(scores, saved.scores);
		if (Array.isArray(saved.remarks)) replaceContents(remarks, saved.remarks);
		if (saved.version === DATA_VERSION) {
			if (Array.isArray(saved.students)) replaceContents(students, saved.students);
			if (Array.isArray(saved.classes)) replaceContents(classes, saved.classes);
			if (Array.isArray(saved.classSubjects)) replaceContents(classSubjects, saved.classSubjects);
		}
	} catch {
		// A corrupt save must never stop the app opening; fall back to the baseline.
	}
}

/** Save the current state. Call after every change. */
export function persist(): void {
	if (typeof localStorage === 'undefined') return;
	try {
		localStorage.setItem(KEY, JSON.stringify({ version: DATA_VERSION, students, classes, classSubjects, scores, remarks }));
	} catch {
		// Storage full or blocked: the in-memory copy still works for this session.
	}
}

/** Throw away this device's changes and go back to the shipped data. */
export function resetToBaseline(): void {
	if (typeof localStorage !== 'undefined') localStorage.removeItem(KEY);
	if (typeof location !== 'undefined') location.reload();
}

load();

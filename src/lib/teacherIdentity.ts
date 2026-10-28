// ============================================================================
// Who is using this device, and what they teach. Nothing is fetched: the
// school's real classes and subjects are hardcoded in teacherData.ts, and the
// teacher ticks their own subjects/classes once. That choice is kept in this
// browser's localStorage, and every "my classes" / "my assignments" list in
// the app is derived from it.
//
// There is no staff list or admin-made assignment data to read yet (the live
// project has no staff rows). When real auth and admin assignments arrive,
// this file is the one place that changes -- the pages only call the
// functions below.
// ============================================================================

import { subjects, classes, classSubjects } from './teacherData';

const KEY = 'tc_teacher_profile';

export interface TeacherProfile {
	name: string;
	subjectIds: string[];
	classIds: string[];
	/** Classes (a subset of classIds) this teacher is the class teacher of. */
	classTeacherIds: string[];
}

export function getProfile(): TeacherProfile | null {
	if (typeof localStorage === 'undefined') return null;
	try {
		const raw = localStorage.getItem(KEY);
		if (!raw) return null;
		const p = JSON.parse(raw) as TeacherProfile;
		const validSubjects = new Set(subjects.map((s) => s.id));
		const validClasses = new Set(classes.map((c) => c.id));
		return {
			name: p.name ?? '',
			subjectIds: (p.subjectIds ?? []).filter((id) => validSubjects.has(id)),
			classIds: (p.classIds ?? []).filter((id) => validClasses.has(id)),
			classTeacherIds: (p.classTeacherIds ?? []).filter((id) => validClasses.has(id))
		};
	} catch {
		return null;
	}
}

export function saveProfile(p: TeacherProfile): void {
	const classTeacherIds = p.classTeacherIds.filter((id) => p.classIds.includes(id));
	localStorage.setItem(KEY, JSON.stringify({ ...p, name: p.name.trim(), classTeacherIds }));
}

/** A class this teacher just created becomes one of their own classes. */
export function addClassToProfile(classId: string): void {
	const p = getProfile();
	if (!p || p.classIds.includes(classId)) return;
	saveProfile({ ...p, classIds: [...p.classIds, classId] });
}

export function clearProfile(): void {
	localStorage.removeItem(KEY);
}

/** Truthy once the teacher has set up their subjects/classes on this device. */
export function getActiveStaffId(): string | null {
	const p = getProfile();
	return p && (p.subjectIds.length > 0 || p.classIds.length > 0) ? 'this-device' : null;
}

export interface Assignment {
	subject_id: string;
	subject_name: string;
	class_id: string;
	class_label: string;
}

/** Every (subject, class) pair this teacher can open a score sheet for. */
export function listMyAssignments(_staffId?: string): Assignment[] {
	const p = getProfile();
	if (!p) return [];
	const mySubjects = new Set(p.subjectIds);
	const myClasses = new Set(p.classIds);
	const subjectName = new Map(subjects.map((s) => [s.id, s.name]));
	const classRec = new Map(classes.map((c) => [c.id, c]));
	const out: Assignment[] = [];
	for (const cs of classSubjects) {
		if (!mySubjects.has(cs.subject_id) || !myClasses.has(cs.class_id)) continue;
		out.push({
			subject_id: cs.subject_id,
			subject_name: subjectName.get(cs.subject_id)!,
			class_id: cs.class_id,
			class_label: classRec.get(cs.class_id)!.label
		});
	}
	return out.sort(
		(a, b) =>
			(classRec.get(a.class_id)!.sort_order - classRec.get(b.class_id)!.sort_order) ||
			a.subject_name.localeCompare(b.subject_name)
	);
}

export interface MyClass {
	id: string;
	label: string;
	is_class_teacher: boolean;
}

/** The classes this teacher is attached to, in school order. */
export function listMyClasses(_staffId?: string): MyClass[] {
	const p = getProfile();
	if (!p) return [];
	return classes
		.filter((c) => p.classIds.includes(c.id))
		.sort((a, b) => a.sort_order - b.sort_order)
		.map((c) => ({ id: c.id, label: c.label, is_class_teacher: p.classTeacherIds.includes(c.id) }));
}

/**
 * What the read-only broadsheet shows: for each of the teacher's classes, the
 * subjects to include. In a class they are class teacher of, that is every
 * subject the class studies; elsewhere, only their own subjects.
 */
export function broadsheetScope(): { classId: string; label: string; subjectIds: string[] }[] {
	const p = getProfile();
	if (!p) return [];
	return listMyClasses().map((c) => {
		const studied = classSubjects.filter((cs) => cs.class_id === c.id).map((cs) => cs.subject_id);
		const subjectIds = c.is_class_teacher ? studied : studied.filter((id) => p.subjectIds.includes(id));
		return { classId: c.id, label: c.label, subjectIds };
	});
}

import { students, classes, classSubjects, remarks, scores, currentTerm, type ClassRecord, type RemarkRecord } from './teacherData';
import { persist } from './localState';

// ============================================================================
// Plain operations on the hardcoded arrays in teacherData.ts. Same function
// names/signatures as when this talked to Supabase, so roster/+page.svelte
// and every other caller needed no changes beyond dropping the auth check --
// but there's no database underneath this anymore, no RLS, no RPC, no
// network. Changes are saved on this device by localState.ts; syncing them
// back to the admin database comes with real auth, later.
// ============================================================================

export interface Student {
	id: string;
	full_name: string;
	class_id: string;
	active: boolean;
	deleted_at: string | null;
	repeating: boolean;
	repeat_assigned_at: string | null;
	repeat_pardoned_at: string | null;
	portrait_url: string | null;
	bio: string | null;
}

export interface NewStudentInput {
	full_name: string;
	class_id: string;
}

// Same TCH-<year>-<NNN> shape as the real roster; next number after the highest in use.
function nextStudentId(): string {
	const max = Math.max(0, ...students.map((s) => Number(s.id.slice(-3))));
	return `TCH-2025-${String(max + 1).padStart(3, '0')}`;
}

/** Add a student to the roster. */
export async function addStudent(input: NewStudentInput): Promise<Student> {
	const student: Student = {
		id: nextStudentId(),
		full_name: input.full_name,
		class_id: input.class_id,
		active: true,
		deleted_at: null,
		repeating: false,
		repeat_assigned_at: null,
		repeat_pardoned_at: null,
		portrait_url: null,
		bio: null
	};
	students.push(student);
	persist();
	return student;
}

function findStudent(id: string): Student {
	const s = students.find((s) => s.id === id);
	if (!s) throw new Error(`No such student: ${id}`);
	return s;
}

/** Remove a student from the roster (soft delete -- sets active=false). */
export async function removeStudent(id: string): Promise<void> {
	const s = findStudent(id);
	s.active = false;
	s.deleted_at = new Date().toISOString();
	persist();
}

/** Undo a soft delete. */
export async function restoreStudent(id: string): Promise<void> {
	const s = findStudent(id);
	s.active = true;
	s.deleted_at = null;
	persist();
}

/** Permanently erase a student -- a real hard delete, cascades to scores/remarks. */
export async function permanentlyEraseStudent(id: string): Promise<void> {
	const idx = students.findIndex((s) => s.id === id);
	if (idx === -1) return;
	const id_ = students[idx].id;
	students.splice(idx, 1);
	// Same cascade the database had: a student's scores and remarks go with them.
	for (let i = scores.length - 1; i >= 0; i--) if (scores[i].student_id === id_) scores.splice(i, 1);
	for (let i = remarks.length - 1; i >= 0; i--) if (remarks[i].student_id === id_) remarks.splice(i, 1);
	persist();
}

/** Every student on the roster (or one class's, if `classId` is given). */
export async function listRoster(classId?: string): Promise<Student[]> {
	return classId ? students.filter((s) => s.class_id === classId) : [...students];
}

/** Assign a student to repeat their current class. */
export async function assignRepeat(id: string): Promise<void> {
	const s = findStudent(id);
	s.repeating = true;
	s.repeat_assigned_at = new Date().toISOString();
	persist();
}

/** Reverse a repeat assignment. Deliberately leaves repeat_assigned_at set. */
export async function pardonRepeat(id: string): Promise<void> {
	const s = findStudent(id);
	s.repeating = false;
	s.repeat_pardoned_at = new Date().toISOString();
	persist();
}

/** Set or clear a student's portrait link. */
export async function setPortraitUrl(id: string, url: string | null): Promise<void> {
	const s = findStudent(id);
	s.portrait_url = url?.trim() || null;
	persist();
}

/** Set or clear a student's bio. */
export async function setBio(id: string, bio: string | null): Promise<void> {
	const s = findStudent(id);
	s.bio = bio?.trim() || null;
	persist();
}

export type ClassInfo = ClassRecord;

/** Every class the school currently has, in tab order. */
export async function listClasses(): Promise<ClassInfo[]> {
	return [...classes].sort((a, b) => a.sort_order - b.sort_order);
}

/**
 * Adds a new arm (JSS) or department (SS) at a given level. Mirrors the
 * database's add_class() (0011): same id and label rules, placed beside its
 * siblings in tab order, one class per stage+level+arm. Unlike the database
 * function, the new class also starts with the subjects of a sibling arm at
 * the same level, so it is usable straight away (admin can change them later).
 */
export async function addClass(
	stage: 'JSS' | 'SS',
	level: 1 | 2 | 3,
	arm: string,
	label?: string
): Promise<ClassInfo> {
	const armName = arm.trim();
	if (!armName) throw new Error('arm/department name is required');
	if (classes.some((c) => c.stage === stage && c.level === level && c.arm.toLowerCase() === armName.toLowerCase())) {
		throw new Error(`${stage}${level} ${armName} already exists`);
	}
	const id = stage === 'JSS' ? `JSS${level}${armName}` : `SS${level} ${armName}`;
	const defaultLabel = stage === 'JSS' ? id : `SS${level} ${armName.slice(0, 3)}`;

	// Land after the last sibling at this level (else after this stage, else at the end).
	const anchors =
		classes.filter((c) => c.stage === stage && c.level === level).length > 0
			? classes.filter((c) => c.stage === stage && c.level === level)
			: classes.filter((c) => c.stage === stage);
	const insertAfter = anchors.length > 0 ? Math.max(...anchors.map((c) => c.sort_order)) : Math.max(0, ...classes.map((c) => c.sort_order));
	for (const c of classes) if (c.sort_order > insertAfter) c.sort_order++;

	const cls: ClassInfo = { id, label: label?.trim() || defaultLabel, arm: armName, stage, level, sort_order: insertAfter + 1 };
	classes.push(cls);

	const sibling = classes.find((c) => c.id !== id && c.stage === stage && c.level === level);
	if (sibling) {
		for (const cs of classSubjects.filter((x) => x.class_id === sibling.id)) {
			classSubjects.push({ class_id: id, subject_id: cs.subject_id });
		}
	}
	persist();
	return cls;
}

/** True for the one level every junior arm eventually leaves through -- JSS3. */
export function isGraduatingJuniorClass(cls: ClassInfo): boolean {
	return cls.stage === 'JSS' && cls.level === 3;
}

/** True for the holding class promoted JSS3 students land in before a department is picked. */
export function isPendingAssignment(cls: ClassInfo): boolean {
	return cls.stage === 'SS' && cls.level === 1 && cls.arm === 'Unassigned';
}

/** Every SS1 class a JSS3 student could promote into. */
export function promotionTargets(classList: ClassInfo[]): ClassInfo[] {
	return classList.filter((c) => c.stage === 'SS' && c.level === 1 && c.arm !== 'Unassigned');
}

/** Every OTHER arm/department at the same stage+level a student could switch into. */
export function classSwitchTargets(current: ClassInfo, classList: ClassInfo[]): ClassInfo[] {
	return classList.filter(
		(c) =>
			c.stage === current.stage &&
			c.level === current.level &&
			c.id !== current.id &&
			c.arm !== 'Unassigned'
	);
}

/** Assigns a pending (post-promotion, Unassigned) student their department. */
export async function assignDepartment(id: string, department: string): Promise<void> {
	await moveStudentToClass(id, `SS1 ${department}`);
}

/** A pending student sent back to repeat a specific JSS3 class. */
export async function sendPendingToRepeatJSS3(id: string, jss3ClassId: string): Promise<void> {
	const s = findStudent(id);
	s.class_id = jss3ClassId;
	s.repeating = true;
	s.repeat_assigned_at = new Date().toISOString();
	persist();
}

/** Moves a student to a different class. */
export async function moveStudentToClass(id: string, newClassId: string): Promise<void> {
	const s = findStudent(id);
	s.class_id = newClassId;
	persist();
}

export type Remark = RemarkRecord;

/** The current term's id. */
export async function getCurrentTermId(): Promise<string | null> {
	return currentTerm.id;
}

/** Remarks for a set of students for the current term. */
export async function listRemarksForTerm(studentIds: string[], termId: string): Promise<Map<string, Remark>> {
	const map = new Map<string, Remark>();
	for (const r of remarks) {
		if (r.term_id === termId && studentIds.includes(r.student_id)) map.set(r.student_id, r);
	}
	return map;
}

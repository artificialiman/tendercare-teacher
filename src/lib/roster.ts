import { students, classes, remarks, currentTerm, type ClassRecord, type RemarkRecord } from './teacherData';

// ============================================================================
// Plain operations on the hardcoded arrays in teacherData.ts. Same function
// names/signatures as when this talked to Supabase, so roster/+page.svelte
// and every other caller needed no changes beyond dropping the auth check --
// but there's no database underneath this anymore, no RLS, no RPC, no
// network. A reload resets everything, same as teacherData.ts's comment
// says. Real persistence returns when a real backend does.
// ============================================================================

export interface Student {
	id: string;
	full_name: string;
	class_id: string;
	active: boolean;
	created_at: string;
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

function nextStudentId(): string {
	return `TCH-TMP-${String(students.length + 1).padStart(3, '0')}`;
}

/** Add a student to the roster. */
export async function addStudent(input: NewStudentInput): Promise<Student> {
	const student: Student = {
		id: nextStudentId(),
		full_name: input.full_name,
		class_id: input.class_id,
		active: true,
		created_at: new Date().toISOString(),
		deleted_at: null,
		repeating: false,
		repeat_assigned_at: null,
		repeat_pardoned_at: null,
		portrait_url: null,
		bio: null
	};
	students.push(student);
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
}

/** Undo a soft delete. */
export async function restoreStudent(id: string): Promise<void> {
	const s = findStudent(id);
	s.active = true;
	s.deleted_at = null;
}

/** Permanently erase a student -- a real hard delete, cascades to scores/remarks. */
export async function permanentlyEraseStudent(id: string): Promise<void> {
	const idx = students.findIndex((s) => s.id === id);
	if (idx === -1) return;
	students.splice(idx, 1);
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
}

/** Reverse a repeat assignment. Deliberately leaves repeat_assigned_at set. */
export async function pardonRepeat(id: string): Promise<void> {
	const s = findStudent(id);
	s.repeating = false;
	s.repeat_pardoned_at = new Date().toISOString();
}

/** Set or clear a student's portrait link. */
export async function setPortraitUrl(id: string, url: string | null): Promise<void> {
	const s = findStudent(id);
	s.portrait_url = url?.trim() || null;
}

/** Set or clear a student's bio. */
export async function setBio(id: string, bio: string | null): Promise<void> {
	const s = findStudent(id);
	s.bio = bio?.trim() || null;
}

export type ClassInfo = ClassRecord;

/** Every class the school currently has, in tab order. */
export async function listClasses(): Promise<ClassInfo[]> {
	return [...classes].sort((a, b) => a.sort_order - b.sort_order);
}

/** Adds a new arm (JSS) or department (SS) at a given level. */
export async function addClass(
	stage: 'JSS' | 'SS',
	level: 1 | 2 | 3,
	arm: string,
	label?: string
): Promise<ClassInfo> {
	const id = `${stage}${level} ${arm.trim()}`;
	const maxOrder = Math.max(0, ...classes.map((c) => c.sort_order));
	const cls: ClassInfo = {
		id,
		label: label?.trim() || id,
		arm: arm.trim(),
		stage,
		level,
		sort_order: maxOrder + 1
	};
	classes.push(cls);
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
}

export interface PromotionResult {
	promoted_count: number;
	graduated_count: number;
	pending_assignment_count: number;
}

let promotionRun = false;

/** Runs the September 1st promotion job. Single-use per cycle, same as the real one. */
export async function runPromotion(): Promise<PromotionResult> {
	if (promotionRun) {
		throw new Error('Promotion has already been run for this cycle.');
	}
	let promoted = 0;
	let graduated = 0;
	let pending = 0;
	for (const s of students) {
		if (!s.active || s.repeating) continue;
		const cls = classes.find((c) => c.id === s.class_id);
		if (!cls) continue;
		if (cls.stage === 'JSS' && cls.level < 3) {
			const target = classes.find((c) => c.stage === 'JSS' && c.level === cls.level + 1 && c.arm === cls.arm);
			if (target) {
				s.class_id = target.id;
				promoted++;
			}
		} else if (cls.stage === 'JSS' && cls.level === 3) {
			s.class_id = 'SS1 Unassigned';
			pending++;
		} else if (cls.stage === 'SS' && cls.level < 3) {
			const target = classes.find((c) => c.stage === 'SS' && c.level === cls.level + 1 && c.arm === cls.arm);
			if (target) {
				s.class_id = target.id;
				promoted++;
			}
		} else if (cls.stage === 'SS' && cls.level === 3) {
			s.active = false;
			s.deleted_at = new Date().toISOString();
			graduated++;
		}
	}
	promotionRun = true;
	return { promoted_count: promoted, graduated_count: graduated, pending_assignment_count: pending };
}

/** Whether calling runPromotion() right now would be rejected. */
export async function checkPromotionAlreadyRun(): Promise<boolean> {
	return promotionRun;
}

/** Moves a student to a different class. */
export async function moveStudentToClass(id: string, newClassId: string): Promise<void> {
	const s = findStudent(id);
	s.class_id = newClassId;
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

import { supabase } from '$lib/supabase';

/**
 * A lightweight "which teacher am I" layer, separate from Supabase Auth.
 *
 * The existing shared staff/admin sign-in (0003_staff_auth_roles.sql,
 * wired in login/+page.svelte) is unchanged and still gates every real
 * write through RLS -- this does not replace it or weaken it. Real
 * per-teacher Supabase Auth accounts are deliberately deferred (staged in
 * staff.auth_user_id / is_active_staff(), 0013) until they're actually
 * needed, by direct instruction.
 *
 * What's missing in the meantime is purely a UX problem: once signed in
 * with the shared account, the app has no idea which real person is
 * sitting at the keyboard, so every picker has had to show the whole
 * school. This picks a real row from the `staff` table (no password, same
 * pattern as the no-gate.html / tendercare-teacher.html reference shells'
 * name picker) and remembers it locally, purely for display and for
 * scoping the subject/class pickers -- never for authorization. Nothing
 * here is sent to the server as a credential; a write's actual permission
 * still comes entirely from the shared session's JWT role claim.
 */

const LS_KEY = 'tc_active_staff_id';

export interface StaffMember {
	id: string;
	full_name: string;
	staff_type: 'part_time' | 'full_time' | 'corps_member';
	is_class_teacher: boolean;
}

export function getActiveStaffId(): string | null {
	return localStorage.getItem(LS_KEY);
}

export function setActiveStaffId(id: string): void {
	localStorage.setItem(LS_KEY, id);
}

export function clearActiveStaffId(): void {
	localStorage.removeItem(LS_KEY);
}

/** Every active staff row, for the name-picker list. */
export async function listActiveStaff(): Promise<StaffMember[]> {
	const { data, error } = await supabase
		.from('staff')
		.select('id, full_name, staff_type, is_class_teacher')
		.eq('active', true)
		.order('full_name');
	if (error) throw error;
	return (data ?? []) as StaffMember[];
}

/** The currently-picked staff row, or null if none picked yet or it's gone (deactivated, deleted). */
export async function getActiveStaff(): Promise<StaffMember | null> {
	const id = getActiveStaffId();
	if (!id) return null;
	const { data, error } = await supabase
		.from('staff')
		.select('id, full_name, staff_type, is_class_teacher')
		.eq('id', id)
		.eq('active', true)
		.maybeSingle();
	if (error) throw error;
	if (!data) {
		clearActiveStaffId();
		return null;
	}
	return data as StaffMember;
}

export interface Assignment {
	subject_id: string;
	subject_name: string;
	class_id: string;
	class_label: string;
}

/**
 * Real (subject, class) pairs this staff member can open a score sheet
 * for -- the join staff_subjects x staff_classes x class_subjects
 * described in 0022's comment. Requires that migration to be applied to
 * the live project; until then this throws a clear "missing table" error
 * rather than silently returning an empty/fabricated list, same honest-
 * failure pattern as NOTES.md's #/feed and #/access-code.
 */
export async function listMyAssignments(staffId: string): Promise<Assignment[]> {
	const [subjectsRes, classesRes] = await Promise.all([
		supabase
			.from('staff_subjects')
			.select('subject_id, subjects(id, name)')
			.eq('staff_id', staffId),
		supabase.from('staff_classes').select('class_id, classes(id, label)').eq('staff_id', staffId)
	]);
	if (subjectsRes.error) throw subjectsRes.error;
	if (classesRes.error) throw classesRes.error;

	const myClassIds = new Set((classesRes.data ?? []).map((r: any) => r.class_id));
	const mySubjects = (subjectsRes.data ?? []) as any[];
	if (mySubjects.length === 0 || myClassIds.size === 0) return [];

	const subjectIds = mySubjects.map((r) => r.subject_id);
	const { data: csRows, error: csError } = await supabase
		.from('class_subjects')
		.select('subject_id, classes(id, label)')
		.in('subject_id', subjectIds);
	if (csError) throw csError;

	const out: Assignment[] = [];
	for (const row of csRows ?? []) {
		const cls = (row as any).classes;
		if (!cls || !myClassIds.has(cls.id)) continue;
		const subj = mySubjects.find((s) => s.subject_id === (row as any).subject_id)?.subjects;
		if (!subj) continue;
		out.push({ subject_id: subj.id, subject_name: subj.name, class_id: cls.id, class_label: cls.label });
	}
	return out;
}

export interface MyClass {
	id: string;
	label: string;
	is_class_teacher: boolean;
}

/**
 * Classes this staff member is attached to via staff_classes (0022), in the
 * school's own sort order. Drives the attendance/roster pickers so a
 * teacher only sees, and can only open, their own classes.
 */
export async function listMyClasses(staffId: string): Promise<MyClass[]> {
	const { data, error } = await supabase
		.from('staff_classes')
		.select('class_id, is_class_teacher, classes(id, label, sort_order)')
		.eq('staff_id', staffId);
	if (error) throw error;
	return ((data ?? []) as any[])
		.filter((r) => r.classes)
		.sort((a, b) => (a.classes.sort_order ?? 0) - (b.classes.sort_order ?? 0))
		.map((r) => ({ id: r.classes.id, label: r.classes.label, is_class_teacher: r.is_class_teacher }));
}

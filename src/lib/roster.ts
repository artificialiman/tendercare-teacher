import { supabase } from '$lib/supabase';

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
}

export interface NewStudentInput {
	full_name: string;
	class_id: string;
}

/**
 * Add a student to the roster. This is the ONLY write path that creates a
 * student anywhere in the suite — tendercare-web and tendercare-portal have
 * no write access to this table at all (enforced by RLS, not just by
 * omission in their UI). The new student is immediately visible to every
 * other app on their next read, since there's no separate copy to update.
 *
 * Calls the create_student() Postgres function (0004_atomic_student_id.sql)
 * rather than reading the current max ID and inserting as two separate
 * round trips — that older approach raced when two staff added a student
 * at close to the same moment. The ID allocation and the insert now happen
 * inside a single database transaction, so concurrent calls genuinely
 * serialize instead of computing the same "next" ID.
 */
export async function addStudent(input: NewStudentInput): Promise<Student> {
	const { data, error } = await supabase.rpc('create_student', {
		p_full_name: input.full_name,
		p_class_id: input.class_id
	});
	if (error) throw error;
	return data as Student;
}

/**
 * Remove a student from the roster (soft delete — see the long comment in
 * 0001_core_schema.sql for why). This is the single action that makes a
 * student disappear from the teacher dashboard, the result/transcript
 * portal, the student directory, and the feed — all in one write, because
 * every one of those reads `students` with `active = true`.
 */
export async function removeStudent(id: string): Promise<void> {
	const {
		data: { user }
	} = await supabase.auth.getUser();
	const { error } = await supabase
		.from('students')
		.update({ active: false, deleted_at: new Date().toISOString(), deleted_by: user?.id ?? null })
		.eq('id', id);
	if (error) throw error;
}

/** Undo a soft delete — puts the student back on every app's roster. */
export async function restoreStudent(id: string): Promise<void> {
	const { error } = await supabase
		.from('students')
		.update({ active: true, deleted_at: null, deleted_by: null })
		.eq('id', id);
	if (error) throw error;
}

/**
 * Permanently erase a student — a real hard delete. This is deliberately a
 * separate, more clearly-labeled action from removeStudent(), because unlike
 * a soft delete it cascades through ON DELETE CASCADE to scores, remarks,
 * portal_credentials, feed_comments, and feed_likes — actual academic
 * history is gone, not just hidden. Reserved for genuine mistakes (duplicate
 * entry, wrong school), not routine "student left" removals.
 */
export async function permanentlyEraseStudent(id: string): Promise<void> {
	const { error } = await supabase.from('students').delete().eq('id', id);
	if (error) throw error;
}

export async function listRoster(classId?: string): Promise<Student[]> {
	let query = supabase.from('students').select('*').order('id');
	if (classId) query = query.eq('class_id', classId);
	const { data, error } = await query;
	if (error) throw error;
	return data as Student[];
}

/**
 * Assign a student to repeat their current class. The September 1st
 * promotion job checks `repeating` and skips advancing this student --
 * see the promotion function's own comment for how it consults this.
 * repeat_assigned_at is set once and never cleared by a pardon, so the
 * history survives even after the flag is turned back off.
 */
export async function assignRepeat(id: string): Promise<void> {
	const { error } = await supabase
		.from('students')
		.update({ repeating: true, repeat_assigned_at: new Date().toISOString() })
		.eq('id', id);
	if (error) throw error;
}

/**
 * Reverse a repeat assignment. Deliberately does NOT clear
 * repeat_assigned_at -- "was this student ever held back" should stay
 * answerable after a pardon, only "are they currently held back" flips.
 */
export async function pardonRepeat(id: string): Promise<void> {
	const { error } = await supabase
		.from('students')
		.update({ repeating: false, repeat_pardoned_at: new Date().toISOString() })
		.eq('id', id);
	if (error) throw error;
}

/**
 * Set or clear a student's portrait link. A link, not an upload -- see
 * the column comment in 0005_repeat_pardon_portrait.sql. Passing null
 * or an empty string clears it back to "no portrait set".
 */
export async function setPortraitUrl(id: string, url: string | null): Promise<void> {
	const { error } = await supabase
		.from('students')
		.update({ portrait_url: url?.trim() || null })
		.eq('id', id);
	if (error) throw error;
}

export interface ClassInfo {
	id: string;
	label: string;
	arm: string; // JSS arm letter ('A', 'B', ...) or SS department name ('Science', 'Actuarial', ...)
	stage: 'JSS' | 'SS';
	level: 1 | 2 | 3;
	sort_order: number;
}

/**
 * Every class the school currently has, in tab order. Not hardcoded to "2
 * arms per junior level, 2 departments per senior level" -- that was seed
 * data, never a ceiling. Any junior level can end up with any number of
 * arms, any senior level with any number of departments; this always
 * reflects whatever actually exists in `classes` right now.
 */
export async function listClasses(): Promise<ClassInfo[]> {
	const { data, error } = await supabase
		.from('classes')
		.select('id, label, arm, stage, level, sort_order')
		.order('sort_order');
	if (error) throw error;
	return data as ClassInfo[];
}

/**
 * Adds a new arm (JSS) or department (SS) at a given level -- calls the
 * add_class() Postgres function (0011_extensible_classes.sql), which does
 * the id/label naming and the sort-order bookkeeping atomically so the new
 * class lands grouped with its siblings rather than always at the end.
 */
export async function addClass(
	stage: 'JSS' | 'SS',
	level: 1 | 2 | 3,
	arm: string,
	label?: string
): Promise<ClassInfo> {
	const { data, error } = await supabase.rpc('add_class', {
		p_stage: stage,
		p_level: level,
		p_arm: arm.trim(),
		p_label: label?.trim() || null
	});
	if (error) throw error;
	return data as ClassInfo;
}

/** True for the one level every junior arm eventually leaves through -- JSS3. */
export function isGraduatingJuniorClass(cls: ClassInfo): boolean {
	return cls.stage === 'JSS' && cls.level === 3;
}

/**
 * True for the holding class run_promotion() (0012_run_promotion.sql)
 * drops former JSS3 students into -- 'SS1 Unassigned'. These students
 * haven't been given a department yet; the roster UI shows the
 * Science/Actuarial/Repeat/Remove assignment flow for them instead of the
 * ordinary switch-class button.
 */
export function isPendingAssignment(cls: ClassInfo): boolean {
	return cls.stage === 'SS' && cls.level === 1 && cls.arm === 'Unassigned';
}

/**
 * Every SS1 class a JSS3 student could promote into -- however many
 * departments actually exist, not a fixed pair. Excludes the Unassigned
 * holding class itself, since that's not a real destination.
 */
export function promotionTargets(classes: ClassInfo[]): ClassInfo[] {
	return classes.filter((c) => c.stage === 'SS' && c.level === 1 && c.arm !== 'Unassigned');
}

/**
 * Every OTHER arm (JSS) or department (SS) at the same stage+level a
 * student could switch into -- could be one alternative (today's A/B or
 * Science/Actuarial split) or several, once a level has 3+ branches.
 * Works for junior arms and senior departments alike -- switching arms is
 * the same operation as switching departments, just one level down.
 * Excludes any Unassigned holding class -- that's an internal promotion
 * state, not somewhere a student gets manually switched into.
 */
export function classSwitchTargets(current: ClassInfo, classes: ClassInfo[]): ClassInfo[] {
	return classes.filter(
		(c) =>
			c.stage === current.stage &&
			c.level === current.level &&
			c.id !== current.id &&
			c.arm !== 'Unassigned'
	);
}

/**
 * Assigns a pending (post-promotion, Unassigned) student their department
 * -- the one piece of the JSS3->SS1 move that's never automatic.
 */
export async function assignDepartment(id: string, department: string): Promise<void> {
	await moveStudentToClass(id, `SS1 ${department}`);
}

/**
 * A pending student whose department assignment turns out to actually be
 * "repeat JSS3" (e.g. a result came in after promotion already ran) --
 * moves them back to a specific JSS3 class and marks them repeating in
 * one step, rather than leaving them in limbo between two write calls.
 */
export async function sendPendingToRepeatJSS3(id: string, jss3ClassId: string): Promise<void> {
	const { error } = await supabase
		.from('students')
		.update({ class_id: jss3ClassId, repeating: true, repeat_assigned_at: new Date().toISOString() })
		.eq('id', id);
	if (error) throw error;
}

export interface PromotionResult {
	promoted_count: number;
	graduated_count: number;
	pending_assignment_count: number;
}

/**
 * Runs the September 1st promotion job -- calls run_promotion()
 * (0012_run_promotion.sql). Whole-roster, one-shot, not something to
 * retry casually -- the caller (the attendance page) gates this behind
 * its own multi-step confirm before ever calling here.
 */
export async function runPromotion(): Promise<PromotionResult> {
	const { data, error } = await supabase.rpc('run_promotion');
	if (error) throw error;
	const row = (Array.isArray(data) ? data[0] : data) as PromotionResult;
	return row;
}

/**
 * Moves a student to a different class -- used for both the JSS3->SS1
 * promotion (staff picks which SS1 department, since that's the one
 * branch point in an otherwise straight-line promotion path) and for a
 * senior student switching department after they've already been placed.
 * A student's id never changes here -- promotion/department changes are
 * always a class_id update, never an id event (id events are only ever
 * graduation + the one-year-later recycling, see 0008).
 */
export async function moveStudentToClass(id: string, newClassId: string): Promise<void> {
	const { error } = await supabase.from('students').update({ class_id: newClassId }).eq('id', id);
	if (error) throw error;
}

export interface Remark {
	student_id: string;
	term_id: string;
	teacher_remark: string | null;
	principal_remark: string | null;
	updated_at: string;
}

/**
 * The current term_id (terms.is_current = true). Used only to know
 * which term's remark to display -- there's no write path here
 * anymore. Remarks are auto-assigned by a trigger on the scores table
 * (0006_auto_remarks.sql) the moment a student's CA/Exam/Total are
 * complete for a term, computed from their average -- never typed by
 * staff. This file only reads what the trigger already wrote.
 */
export async function getCurrentTermId(): Promise<string | null> {
	const { data, error } = await supabase.from('terms').select('id').eq('is_current', true).maybeSingle();
	if (error) throw error;
	return data?.id ?? null;
}

/**
 * Fetch remarks for every student in a class for the current term, in
 * one query rather than one per student -- keyed by student_id so the
 * roster UI can look each one up as it renders rows. A student with no
 * row here simply hasn't had their term completed yet (see the
 * migration's clear-on-incomplete behavior) -- that's a real, expected
 * state, not a loading gap.
 */
export async function listRemarksForTerm(
	studentIds: string[],
	termId: string
): Promise<Map<string, Remark>> {
	if (studentIds.length === 0) return new Map();
	const { data, error } = await supabase
		.from('remarks')
		.select('*')
		.eq('term_id', termId)
		.in('student_id', studentIds);
	if (error) throw error;
	const map = new Map<string, Remark>();
	for (const r of (data ?? []) as Remark[]) map.set(r.student_id, r);
	return map;
}

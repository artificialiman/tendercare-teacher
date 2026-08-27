import { supabase } from '$lib/supabase';

export interface Student {
	id: string;
	full_name: string;
	class_id: string;
	active: boolean;
	created_at: string;
	deleted_at: string | null;
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

export interface Remark {
	student_id: string;
	term_id: string;
	teacher_remark: string | null;
	principal_remark: string | null;
	updated_at: string;
}

/**
 * The current term_id (terms.is_current = true). Remarks are entered
 * against a specific term, and the roster UI only ever edits the
 * current one -- past terms' remarks are part of that term's already-
 * generated static report, not something to retroactively change here.
 */
export async function getCurrentTermId(): Promise<string | null> {
	const { data, error } = await supabase.from('terms').select('id').eq('is_current', true).maybeSingle();
	if (error) throw error;
	return data?.id ?? null;
}

/**
 * Fetch remarks for every student in a class for the current term, in
 * one query rather than one per student -- keyed by student_id so the
 * roster UI can look each one up as it renders rows.
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

/**
 * Write (or update) a student's remarks for a term. RLS on the remarks
 * table (0002_rls_policies.sql) already restricts writes to the
 * `staff` role and read-only self-access for students -- this function
 * doesn't duplicate that check, it relies on it: an unauthorized caller
 * gets rejected by Postgres, not by client-side logic that could be
 * bypassed. student_id + term_id is the table's primary key, so this is
 * a genuine upsert -- no separate "does a row exist yet" read needed.
 */
export async function upsertRemark(
	studentId: string,
	termId: string,
	teacherRemark: string,
	principalRemark: string
): Promise<void> {
	const { error } = await supabase
		.from('remarks')
		.upsert(
			{
				student_id: studentId,
				term_id: termId,
				teacher_remark: teacherRemark.trim() || null,
				principal_remark: principalRemark.trim() || null,
				updated_at: new Date().toISOString()
			},
			{ onConflict: 'student_id,term_id' }
		);
	if (error) throw error;
}

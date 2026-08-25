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
 * The next student ID in the TCH-2025-NNN sequence. Reads the current max
 * across ALL students (not just active ones), so a soft-deleted student's ID
 * is never reissued to someone else — same guarantee the old flat-file
 * roster had by accident (IDs were assigned once, by hand, and never reused).
 */
export async function nextStudentId(): Promise<string> {
	const { data, error } = await supabase
		.from('students')
		.select('id')
		.order('id', { ascending: false })
		.limit(1);
	if (error) throw error;
	const last = data?.[0]?.id ?? 'TCH-2025-000';
	const n = parseInt(last.split('-')[2], 10) + 1;
	return `TCH-2025-${String(n).padStart(3, '0')}`;
}

/**
 * Add a student to the roster. This is the ONLY write path that creates a
 * student anywhere in the suite — tendercare-web and tendercare-portal have
 * no write access to this table at all (enforced by RLS, not just by
 * omission in their UI). The new student is immediately visible to every
 * other app on their next read, since there's no separate copy to update.
 */
export async function addStudent(input: NewStudentInput): Promise<Student> {
	const id = await nextStudentId();
	const { data, error } = await supabase
		.from('students')
		.insert({ id, full_name: input.full_name, class_id: input.class_id })
		.select()
		.single();
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

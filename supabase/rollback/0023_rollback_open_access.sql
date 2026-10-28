-- Removes 0023 completely. Run only if you want the open-access plumbing gone;
-- to merely switch it off, update app_settings instead (see 0023 header).
drop policy if exists "TEMP open access (anon)" on public.students;
drop policy if exists "TEMP open access (anon)" on public.classes;
drop policy if exists "TEMP open access (anon)" on public.subjects;
drop policy if exists "TEMP open access (anon)" on public.class_subjects;
drop policy if exists "TEMP open access (anon)" on public.terms;
drop policy if exists "TEMP open access (anon)" on public.scores;
drop policy if exists "TEMP open access (anon)" on public.remarks;
drop policy if exists "TEMP open access (anon)" on public.staff;
drop policy if exists "TEMP open access (anon)" on public.staff_subjects;
drop policy if exists "TEMP open access (anon)" on public.staff_classes;
revoke execute on function public.create_student(text, text, text, text) from anon;
revoke execute on function public.create_students_bulk(jsonb, text) from anon;
revoke execute on function public.mark_student_graduated(text) from anon;
revoke execute on function public.recycle_alumni_id(text) from anon;
revoke execute on function public.add_class(text, int, text, text) from anon;
revoke execute on function public.run_promotion() from anon;
revoke execute on function public.delete_old_feed_activity(int) from anon;
-- The function bodies keep calling caller_may(); with the policies gone and
-- open_access false they behave exactly like the app_role checks in 0020/0021.
update public.app_settings set value = 'false'::jsonb where key = 'open_access';
